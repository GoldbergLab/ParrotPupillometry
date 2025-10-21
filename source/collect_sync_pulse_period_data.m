function [collected_data, index_info, collected_filled] = collect_sync_pulse_period_data(this_path, next_path, this_drop_info, next_drop_info, this_onset, next_onset, cache, loader, data_slicer, data_sizer, data_combiner, data_drop_fixer, options)
arguments
    this_path char
    next_path char
    this_drop_info
    next_drop_info
    this_onset double
    next_onset double
    cache
    loader = []
    data_slicer = []
    data_sizer = []
    data_combiner = []
    data_drop_fixer = []
    options.MaxCacheSize = 9
    options.Debug = false
    options.DataType {mustBeMember(options.DataType, {'audio', 'video', 'none'})}
end
if options.Debug
    disp('LOADING PULSE PERIOD DATA')
end

% Define utility functions
switch options.DataType
    case 'none'
        % User is going to specify all data handler functions explicitly
    case 'audio'
        if isempty(loader)
            loader = @audioread;
        end
        if isempty(data_slicer)
            data_slicer = @(data, start, stop)data(start:stop, :);
        end
        if isempty(data_sizer)
            data_sizer = @(data)size(data, 1);
        end
        if isempty(data_combiner)
            data_combiner = @(data1, data2)[data1; data2];
        end
        if isempty(data_drop_fixer)
        end
    case 'video'
        if isempty(loader)
            loader = @(path)fastVideoReader(path);
        end
        if isempty(data_slicer)
            data_slicer = @(data, start, stop)data(:, :, :, start:stop);
        end
        if isempty(data_sizer)
            data_sizer = @(data)size(data, 4);
        end
        if isempty(data_combiner)
            data_combiner = @(data1, data2)cat(4, data1, data2);
        end
        if isempty(data_drop_fixer)
        end
end

audio_loader = @audioread;
audio_data_slicer = @(data, start, stop)data(start:stop, :);
audio_data_sizer = @(data)size(data, 1);
audio_data_combiner = @(data1, data2)[data1; data2];
video_loader = @(path)fastVideoReader(path);
video_data_slicer = @(data, start, stop)data(:, :, :, start:stop);
video_data_sizer = @(data)size(data, 4);
video_data_combiner = @(data1, data2)cat(4, data1, data2);


% Load initial file
data = cacheLoadFile(this_path, loader, cache, 'MaxLength', options.MaxCacheSize);

% If data has drops, fix the drops here, and save info about where the drops are
if ~isempty(this_drop_info)
    [data, filled] = data_drop_fixer(data, this_drop_info);
else
    filled = false([1, data_sizer(data)]);
end

% Pulse period starts at pulse onset, of course
start_sample = this_onset;

pulse_spans_two_files = ~strcmp(this_path, next_path);

if ~pulse_spans_two_files
    % Whole pulse period is contained within this file
    end_sample = next_onset-1;
else
    % Pulse period spans two files
    end_sample = data_sizer(data);
end

% Slice data from pulse start to whichever end sample is appropriate
collected_data = data_slicer(data, start_sample, end_sample);
% Collect info about how data was sliced for posterity
index_info = struct();
index_info.path = this_path;
index_info.start_sample = start_sample;
index_info.end_sample = end_sample;
if options.Debug
    [~, name, ext] = fileparts(this_path);
    fprintf('Loading %06d - %06d from %s\n', start_sample, end_sample, [name, ext]);
end

% If data has drops and save info about where the drops are
collected_filled = filled(start_sample:end_sample);

if  pulse_spans_two_files
    % Pulse period spans two files - load second file chunk
    data2 = cacheLoadFile(next_path, loader, cache, 'MaxLength', options.MaxCacheSize);
    if ~isempty(next_drop_info)
        [data2, filled2] = data_drop_fixer(data2, next_drop_info);
    else
        filled2 = false([1, data_sizer(data2)]);
    end

    % Start chunk at the beginning of file 2
    start_sample = 1;
    % And just before next pulse onset
    end_sample = next_onset-1;
    % Slice data from start of file 2 to just before next onset
    next_collected_data = data_slicer(data2, start_sample, end_sample);
    % Combine the previous slice with this one
    collected_data = data_combiner(collected_data, next_collected_data);
    % Combine filled info too
    collected_filled = [collected_filled, filled2(start_sample, end_sample)];
    % Collect info about how data was sliced for posterity
    index_info(2).path = next_path;
    index_info(2).start_sample = start_sample;
    index_info(2).end_sample = end_sample;
    if options.Debug
        [~, name, ext] = fileparts(this_path);
        fprintf('Loading %06d - %06d from %s\n', start_sample, end_sample, [name, ext]);
    end
end

% 
%         % Duplicate previous frame to fill in dropped frames
%         video_data_fixed(:, :, :, chunk_end_fixed+1:chunk_start_fixed-1) = repmat(video_data(:, :, :, source_frame), 1, 1, 1, drop_info(drop_idx).num_dropped);
%         filled(chunk_end_fixed+1:chunk_start_fixed-1) = true;
%         % fprintf('Filling %d:%d from %d x %d\n', chunk_end_fixed+1, chunk_start_fixed-1, source_frame, drop_info(drop_idx).num_dropped);
%     end
% end

function [video_data_fixed, filled] = fillInDroppedVideoFrames(video_data, drop_info)
% Return video data with the frame before any dropped frames duplicated to fill in the missing frames
%   video_data: H x W x 3 X N video array
%   drop_info: struct with fields
%                   - frame_num: original frame number immediately after the dropped frame(s)
%                   - frame_num_cumulative: original frame number, cumulative since the start of the session, immediately after the dropped frame(s)
%                   - frame_time: timestamp of frame immediately after the dropped frame(s)
%                   - last_ID: image ID of the frame before the dropped frame(s)
%                   - this_ID: image ID of the frame after the dropped frame(s)
%                   - num_dropped: How many frames were dropped
video_size = size(video_data);
num_frames = video_size(4);
video_size_fixed = video_size;
num_frames_fixed = num_frames + sum([drop_info.num_dropped]);
video_size_fixed(4) = num_frames_fixed;
video_data_fixed = zeros(video_size_fixed, class(video_data));
drop_spots = [1, [drop_info.frame_num], num_frames+1];

filled = false(1, num_frames_fixed);

chunk_start_fixed = 1;
for drop_idx = 1:length(drop_info)+1
    % Identify start/end of consecutive frames (with no interceding drops)
    chunk_start = drop_spots(drop_idx);
    chunk_end = (drop_spots(drop_idx+1) - 1);
    % Calculate length of chunk
    chunk_size = chunk_end-chunk_start+1;
    % Calculate the end of the chunk in fixed frame numbers
    chunk_end_fixed = chunk_start_fixed + chunk_size - 1;
    % Copy consecutive chunk into output array
    video_data_fixed(:, :, :, chunk_start_fixed:chunk_end_fixed) = video_data(:, :, :, chunk_start:chunk_end);
    % fprintf('Copying %d:%d to %d:%d\n', chunk_start, chunk_end, chunk_start_fixed, chunk_end_fixed);
    if drop_idx <= length(drop_info)
        % Calculate start of next chunk in fixed frame numbers
        chunk_start_fixed = chunk_end_fixed + drop_info(drop_idx).num_dropped + 1;
        % Handle edge case of first frame getting duplicated
        if chunk_end == 0
            source_frame = 1;
        else
            source_frame = chunk_end;
        end
        % Duplicate previous frame to fill in dropped frames
        video_data_fixed(:, :, :, chunk_end_fixed+1:chunk_start_fixed-1) = repmat(video_data(:, :, :, source_frame), 1, 1, 1, drop_info(drop_idx).num_dropped);
        filled(chunk_end_fixed+1:chunk_start_fixed-1) = true;
        % fprintf('Filling %d:%d from %d x %d\n', chunk_end_fixed+1, chunk_start_fixed-1, source_frame, drop_info(drop_idx).num_dropped);
    end
end

function newVideoData = reorientNaneyeVideo(videoData)
w = size(videoData, 2);
h = size(videoData, 1);
n = size(videoData, 4);

newW = 2 * w;
newH = h / 2;

newVideoData = zeros([newH, newW, 3, n], class(videoData));
newVideoData(:, 1:w, :, :) = videoData(1:newH, :, :, :);
newVideoData(:, w+1:end, :, :) = videoData(newH+1:end, :, :, :);


function writeSourceInfo(data_path, index_info, filled)

[folder, name, ~] = fileparts(data_path);

info_path = fullfile(folder, [name '_info.json']);

% Find indices of filled samples/frames
filled_samples = find(filled(:));

source_info.sources = index_info;
source_info.filled_samples = filled_samples;

% Encode as pretty JSON array
json_str = jsonencode(source_info, 'PrettyPrint', true);

% Write to file
fid = fopen(info_path, 'w');
if fid == -1
    error('Could not open %s for writing.', info_path);
end
fwrite(fid, json_str, 'char');
fclose(fid);
