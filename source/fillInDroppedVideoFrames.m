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