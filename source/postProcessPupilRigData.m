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
end

if isempty(sync_struct)
    % If requested, pick the webcam ROI interactively from a video in the
    %   middle of the stream (where the rig is most likely settled and lit).
    if options.IncludeWebcam && istext(options.WebcamROI) && strcmpi(options.WebcamROI, 'GUI')
        webcam_files = findPaths(data_root, options.WebcamFileRegex, 'SearchSubdirectories', false);
        if isempty(webcam_files)
            error('postProcessPupilRigData:noWebcamFilesForGUI', ...
                ['WebcamROI was ''GUI'', but no webcam files matching ''%s'' were ' ...
                 'found in %s.'], options.WebcamFileRegex, data_root);
        end
        middle_file = webcam_files{ceil(numel(webcam_files) / 2)};
        fprintf('Select the webcam sync ROI (click and drag; Accept or Cancel):\n  %s\n', middle_file);
        roi_browser = VideoROI(middle_file);
        if isempty(roi_browser.ROI)
            error('postProcessPupilRigData:roiSelectionCancelled', ...
                'Webcam ROI selection was cancelled - aborting.');
        end
        options.WebcamROI = roi_browser.ROI;
        fprintf('Selected webcam ROI: [%d %d %d %d]\n', options.WebcamROI);
    end

    % If requested, pick the naneye flash ROI(s) interactively. The naneye
    %   video holds the two stacked eyes, so with DualNaneyeSync there are two
    %   ROIs - one per eye - each drawn on that eye's half of the stacked frame.
    if options.IncludeNaneye && istext(options.NaneyeROI) && strcmpi(options.NaneyeROI, 'GUI')
        naneye_files = findPaths(data_root, options.NaneyeFileRegex, 'SearchSubdirectories', false);
        if isempty(naneye_files)
            error('postProcessPupilRigData:noNaneyeFilesForGUI', ...
                ['NaneyeROI was ''GUI'', but no naneye files matching ''%s'' were ' ...
                 'found in %s.'], options.NaneyeFileRegex, data_root);
        end
        middle_file = naneye_files{ceil(numel(naneye_files) / 2)};
        if options.DualNaneyeSync
            num_eyes = 2;
        else
            num_eyes = 1;
        end
        naneye_roi = zeros(num_eyes, 4);
        for eye_idx = 1:num_eyes
            fprintf('Select naneye sync ROI for eye %d of %d (draw on that eye''s half of the stacked frame):\n  %s\n', eye_idx, num_eyes, middle_file);
            roi_browser = VideoROI(middle_file, 'Title', sprintf('Draw sync ROI for naneye eye %d of %d', eye_idx, num_eyes));
            if isempty(roi_browser.ROI)
                error('postProcessPupilRigData:roiSelectionCancelled', ...
                    'Naneye ROI selection was cancelled - aborting.');
            end
            naneye_roi(eye_idx, :) = roi_browser.ROI;
            fprintf('Selected naneye eye %d ROI: [%d %d %d %d]\n', eye_idx, naneye_roi(eye_idx, :));
        end
        options.NaneyeROI = naneye_roi;
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