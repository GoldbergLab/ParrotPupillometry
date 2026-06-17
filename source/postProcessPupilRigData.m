function sync_struct = postProcessPupilRigData(data_root, align_root, options)
arguments
    data_root {mustBeTextScalar}
    align_root {mustBeTextScalar}
    options.PulsesPerFile = 2
    options.SyncStruct = struct.empty()
    options.NaneyeNumIgnoredPulses = 0
    options.WebcamNumIgnoredPulses = 0
    options.AudioNumIgnoredPulses = 0
    options.FileLimit = []
    options.ClickChannel = 1
    options.NaneyeBadSyncFileIdx = []
    options.WebcamBadSyncFileIdx = []
    options.AudioBadSyncFileIdx = []
    options.WebcamROI = [1, 1, 50, 50] % [top left x /top left y /w /h]
    options.NaneyeROI = []  % empty => per-eye defaults in getPupillometryDataAlignment
    options.IncludeNaneye = true
    options.IncludeWebcam = true
    options.DualNaneyeSync = true
    options.NaneyeEyeHeight = 250
    options.NaneyeFileRegex {mustBeText} = 'naneye.*\.avi'
    options.WebcamFileRegex {mustBeText} = 'webcam.*\.avi'
    options.AudioFileRegex {mustBeText} = '.*\.wav'
    options.AudioPulseShape {mustBeMember(options.AudioPulseShape, {'level', 'pair'})} = 'level'
    options.AudioThreshold = 0.01
    options.NaneyeThreshold = 0.5
    options.NaneyeRangeBasedThreshold = true
    options.NaneyeMedianWindow = 20
    options.WebcamThreshold = 0.5
    options.WebcamRangeBasedThreshold = true
    options.WebcamMedianWindow = 20
    options.InsetNaneyeInWebcam = false
    options.InsetScale (1, 1) double = 0.35
end

sync_struct = struct.empty();

if isempty(options.SyncStruct) 
    if istext(options.SyncStruct)
        % Empty string means use the default saved .mat file
        try
            % Get default path for alignment struct .mat file
            default_path = getAlignmentStructPath(data_root);
            % Load data
            S = load(default_path);
            % Attempt to get sync_struct
            sync_struct = S.sync_struct;
        catch ME
            if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
                fprintf('No sync struct found in file %s\n\nGenerating sync_struct...\n', default_path);
            else
                fprintf('Something went wrong loading default sync struct...generating new one...\n')
                disp(ME.message)
            end
            sync_struct = struct.empty();
        end
    end
elseif istext(options.SyncStruct)
    % User passed a non-empty string - try to use it as a path to load from
    try
        % Load data
        S = load(options.SyncStruct);
        % Attempt to get sync_struct
        sync_struct = S.sync_struct;
    catch ME
        if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
            fprintf('No sync struct found in file %s\n\nGenerating sync_struct...\n', options.SyncStruct);
            sync_struct = struct.empty();
        else
            rethrow(ME);
        end
    end
elseif isstruct(options.SyncStruct) && ~isempty(options.SyncStruct)
    sync_struct = options.SyncStruct;
end

if isempty(sync_struct)
    % If requested, pick the webcam ROI interactively. selectROIsFromVideos
    %   starts from a video in the middle of the stream and, if the chosen video
    %   has no sync flash, offers to try the next one.
    if options.IncludeWebcam && istext(options.WebcamROI) && strcmpi(options.WebcamROI, 'GUI')
        webcam_files = findPaths(data_root, options.WebcamFileRegex, 'SearchSubdirectories', false);
        if isempty(webcam_files)
            error('postProcessPupilRigData:noWebcamFilesForGUI', ...
                ['WebcamROI was ''GUI'', but no webcam files matching ''%s'' were ' ...
                 'found in %s.'], options.WebcamFileRegex, data_root);
        end
        options.WebcamROI = selectROIsFromVideos(webcam_files, 1, 'webcam');
        fprintf('Selected webcam ROI: [%d %d %d %d]\n', options.WebcamROI);
    end

    % If requested, pick the naneye flash ROI(s) interactively. The naneye video
    %   holds the two stacked eyes, so with DualNaneyeSync there are two ROIs -
    %   one per eye - each drawn on that eye's half of the stacked frame. Not
    %   every naneye file contains a flash (the period is ~10 s), so
    %   selectROIsFromVideos offers to try the next video if needed.
    if options.IncludeNaneye && istext(options.NaneyeROI) && strcmpi(options.NaneyeROI, 'GUI')
        naneye_files = findPaths(data_root, options.NaneyeFileRegex, 'SearchSubdirectories', false);
        if isempty(naneye_files)
            error('postProcessPupilRigData:noNaneyeFilesForGUI', ...
                ['NaneyeROI was ''GUI'', but no naneye files matching ''%s'' were ' ...
                 'found in %s.'], options.NaneyeFileRegex, data_root);
        end
        if options.DualNaneyeSync
            num_eyes = 2;
        else
            num_eyes = 1;
        end
        naneye_roi = selectROIsFromVideos(naneye_files, num_eyes, 'naneye');
        if num_eyes == 2
            % Assign ROIs to eyes by vertical position rather than draw order:
            %   the upper ROI (smaller center y) is eye 0 (top half of the
            %   stacked frame), the lower one is eye 1 (bottom half).
            roi_center_y = naneye_roi(:, 2) + naneye_roi(:, 4) / 2;
            [~, top_to_bottom] = sort(roi_center_y);
            naneye_roi = naneye_roi(top_to_bottom, :);
        end
        options.NaneyeROI = naneye_roi;
        for eye_idx = 1:num_eyes
            fprintf('  naneye eye %d ROI: [%d %d %d %d]\n', eye_idx - 1, naneye_roi(eye_idx, :));
        end
    end

    % options.SyncStruct is still empty - generate it from scratch
    sync_struct = getPupillometryDataAlignment( ...
        data_root, ...
        'NaneyeNumIgnoredPulses', options.NaneyeNumIgnoredPulses, ...
        'WebcamNumIgnoredPulses', options.WebcamNumIgnoredPulses, ...
        'AudioNumIgnoredPulses', options.AudioNumIgnoredPulses, ...
        'NaneyeBadSyncFileIdx', options.NaneyeBadSyncFileIdx, ...
        'WebcamBadSyncfileIdx', options.WebcamBadSyncFileIdx, ...
        'AudioBadSyncfileIdx', options.AudioBadSyncFileIdx, ...
        'FileLimit', options.FileLimit, ...
        'ClickChannel', options.ClickChannel, ...
        'WebcamROI', options.WebcamROI, ...
        'NaneyeROI', options.NaneyeROI, ...
        'IncludeNaneye', options.IncludeNaneye, ...
        'IncludeWebcam', options.IncludeWebcam, ...
        'DualNaneyeSync', options.DualNaneyeSync, ...
        'NaneyeEyeHeight', options.NaneyeEyeHeight, ...
        'NaneyeFileRegex', options.NaneyeFileRegex, ...
        'WebcamFileRegex', options.WebcamFileRegex, ...
        'AudioFileRegex', options.AudioFileRegex, ...
        'AudioPulseShape', options.AudioPulseShape, ...
        'AudioThreshold', options.AudioThreshold, ...
        'NaneyeThreshold', options.NaneyeThreshold, ...
        'NaneyeRangeBasedThreshold', options.NaneyeRangeBasedThreshold, ...
        'NaneyeMedianWindow', options.NaneyeMedianWindow, ...
        'WebcamThreshold', options.WebcamThreshold, ...
        'WebcamRangeBasedThreshold', options.WebcamRangeBasedThreshold, ...
        'WebcamMedianWindow', options.WebcamMedianWindow ...
        );
end

alignVideosToAudio(sync_struct, align_root, ...
    'PulsesPerFile', options.PulsesPerFile, ...
    'VideoClicks', false, ...
    'ClickChannel', options.ClickChannel, ...
    'IncludeNaneye', options.IncludeNaneye, ...
    'IncludeWebcam', options.IncludeWebcam, ...
    'InsetNaneyeInWebcam', options.InsetNaneyeInWebcam, ...
    'InsetScale', options.InsetScale ...
    );

function rois = selectROIsFromVideos(files, num_rois, stream_name)
% Collect num_rois ROIs with VideoROI, starting from a video in the middle of
%   the list. If the user closes the dialog without a complete set of ROIs (for
%   example because the chosen video does not contain a sync flash), ask whether
%   to abort or try the next video. Tries each video at most once, wrapping
%   around from the middle. Returns a num_rois x 4 matrix, or errors if the user
%   aborts or every video has been tried without a complete selection.
num_files = numel(files);
start_idx = ceil(num_files / 2);
% Order of videos to try: middle first, then forward, wrapping around
order = mod((start_idx - 1) + (0:num_files - 1), num_files) + 1;
for k = 1:num_files
    video_file = files{order(k)};
    fprintf('Select %d %s sync ROI(s) (click and drag; Accept or Cancel):\n  %s\n', ...
        num_rois, stream_name, video_file);
    roi_browser = VideoROI(video_file, 'NumROIs', num_rois, ...
        'Title', sprintf('Draw %d %s sync ROI(s)', num_rois, stream_name));
    rois = roi_browser.ROI;
    if ~isempty(rois) && size(rois, 1) == num_rois
        return
    end
    answer = questdlg(sprintf(['No complete %s ROI selection was made. This video may ' ...
        'not contain a sync flash. Try the next video, or abort?'], stream_name), ...
        'No ROI selected', 'Try next video', 'Abort', 'Try next video');
    if ~strcmp(answer, 'Try next video')
        error('postProcessPupilRigData:roiSelectionCancelled', ...
            '%s ROI selection was aborted.', stream_name);
    end
end
error('postProcessPupilRigData:noFlashVideoFound', ...
    'Tried all %d %s videos without a complete ROI selection. Aborting.', ...
    num_files, stream_name);