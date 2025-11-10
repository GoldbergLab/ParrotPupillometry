function flash_struct = makeVideoSyncStruct(root_directory, ROI, threshold, pulse_time, options)
%       FileRegex: the regular expression to use to filter files in the
%           root directory. Default is '.*\.avi'
arguments
    root_directory
    ROI (1, 4) double = []
    threshold double = 150
    pulse_time double = 0.08
    options.FrameRate double = 30
    options.FileRegex {mustBeText} = '.*\.avi'
    options.MedianWindow double = [],
    options.PlotOnsets (1, 1) logical = false
    options.RangeBasedThreshold (1, 1) logical = false
    options.NumIgnoredFlashes = 0
    options.FileLimit = []
    options.BadSyncFileIdx = []
end

video_files = findPaths(root_directory, options.FileRegex, 'SearchSubdirectories', false);
if ~isempty(options.FileLimit) && length(video_files) > options.FileLimit
    % User requests limited number of video files
    video_files = video_files(1:options.FileLimit);
end
num_files = length(video_files);

% Initialize structure
flash_struct(num_files) = struct();

cumulative_frames = 0;

for k = 1:num_files
    video_file = video_files{k};
    flash_struct(k).path = video_file;
    if ~ismember(k, options.BadSyncFileIdx)
        % User indicates this video should have good sync signal
        [onsets, offsets, num_frames] = findSyncFlashOnsets( ...
            video_file, ...
            ROI, ...
            threshold, ...
            pulse_time, ...
            "FrameRate", options.FrameRate, ...
            'MedianWindow', options.MedianWindow, ...
            'PlotOnsets', options.PlotOnsets, ...
            'RangeBasedThreshold', options.RangeBasedThreshold ...
            );
    else
        % Users indicates sync signal is bad in this file
        %   Leave onsets/offsets empty, just determine number of frames
        onsets = [];
        offsets = [];
        video_info = getVideoInfo(video_file, 'SystemCheck', false);
        num_frames = video_info.numFrames;
    end
    if options.NumIgnoredFlashes > 0
        if length(onsets) <= options.NumIgnoredFlashes
            options.NumIgnoredFlashes = options.NumIgnoredFlashes - length(onsets);
            onsets = [];
            offsets = [];
        else
            onsets(1:options.NumIgnoredFlashes) = [];
            offsets(1:options.NumIgnoredFlashes) = [];
            options.NumIgnoredFlashes = 0;
        end
    end
    flash_struct(k).onsets = onsets;
    flash_struct(k).offsets = offsets;
    flash_struct(k).onsets_cumulative = onsets + cumulative_frames;
    flash_struct(k).offsets_cumulative = offsets + cumulative_frames;
    flash_struct(k).num_frames = num_frames;
    flash_struct(k).ROI = ROI;
    if options.PlotOnsets
        drawnow();
    end
    cumulative_frames = cumulative_frames + num_frames;
end