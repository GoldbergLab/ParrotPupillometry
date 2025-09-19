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
end

video_files = findFiles(root_directory, options.FileRegex, 'SearchSubdirectories', false);
num_files = length(video_files);

% Initialize structure
flash_struct(num_files) = struct();

for k = 1:num_files
    video_file = video_files{k};
    flash_struct(k).path = video_file;
    [onsets, offsets, num_frames] = findSyncFlashOnsets(video_file, ROI, threshold, pulse_time, "FrameRate", options.FrameRate);
    flash_struct(k).onsets = onsets;
    flash_struct(k).offsets = offsets;
    flash_struct(k).num_frames = num_frames;
end