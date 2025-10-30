function flash_struct = addDroppedFramesToFlashStruct(flash_struct, frame_id_wrap_length)
arguments
    flash_struct
    frame_id_wrap_length = []
end

% Keep track of cumulative drops between videos
cumulative_drops = 0;

% Keep track of # of missing videos detected, so we don't have an offset in drop frame number
missing_videos = [];

% Loop over each video
for file_num = 1:length(flash_struct)
    % Construct expected dropped frame file path
    [directory, name, ~] = fileparts(flash_struct(file_num).path);
    dropped_frame_path = fullfile(directory, [name, '.txt']);
    % Check if there is a dropped frame file
    if exist(dropped_frame_path, "file")
        % Initialize dropped frame info struct for this video
        flash_struct(file_num).drop_info = struct();
        % Read dropped frame file
        txt = fileread(dropped_frame_path);
        records = splitlines(txt);
        wraps = 0;
        % Loop over each dropped frame record
        for j = 1:length(records)
            if ~isempty(records{j})
                % Parse dropped frame record
                vals = sscanf(records{j}, '%d - %f - frame_drop: %d=>%d');
                frame_num = vals(1);
                frame_time = vals(2);
                last_ID = vals(3);
                this_ID = vals(4);

                % If we haven't already calculated missing_videos, calculate it now
                if isempty(missing_videos)
                    % Check if there seems to be missing files
                    missing_videos = 0;
                    % Check if all files have the same # of frames or not
                    num_samples_per_file = unique([flash_struct.num_frames]);
                    if ~isscalar(num_samples_per_file)
                        % Files do not all have same length
                        if frame_num > min(num_samples_per_file)
                            % Ok, multiple possible samples per file, and 
                            % the first frame num is greater than the 
                            % minimum, so there could be missing files
                            error('Initial video(s) seem to be missing, and files are not uniform in length - cannot compensate.')
                        else
                            % Doesn't seem like files are missing, we're good
                        end
                    else
                        % All files have same length
                        if frame_num > num_samples_per_file
                            % Calculate how many videos are missing
                            missing_videos = floor(frame_num / num_samples_per_file);
                            warning('Found evidence of %d missing videos in dropped frame info - adjusting frame drops.', missing_videos);
                        end
                    end
                end

                % Calculate number of dropped frames in this record
                num_dropped = this_ID - last_ID - 1;

                if ~isempty(frame_id_wrap_length)
                    % This type of camera does wrap image IDs
                    if num_dropped < 0
                        num_dropped = num_dropped + frame_id_wrap_length;
                        if num_dropped == 0
                            % This is a normal frame wrap, not a frame drop
                            wraps = wraps + 1;
                            continue
                        end
                    end
                end

                % Correct dropped frame record # if there have been wraps instead of dropped frames
                jj = j - wraps;

                % Record drop info in struct
                flash_struct(file_num).drop_info(jj).frame_num = frame_num - flash_struct(file_num).num_frames * (file_num - 1 + missing_videos);
                flash_struct(file_num).drop_info(jj).frame_num_cumulative = frame_num - flash_struct(file_num).num_frames * missing_videos;
                flash_struct(file_num).drop_info(jj).frame_time = frame_time;
                flash_struct(file_num).drop_info(jj).last_ID = last_ID;
                flash_struct(file_num).drop_info(jj).this_ID = this_ID;
                flash_struct(file_num).drop_info(jj).num_dropped = num_dropped;
            end
        end

        % Create fields for drop-corrected onsets and offsets
        flash_struct(file_num).onsets_cumulative_original = flash_struct(file_num).onsets_cumulative;
        flash_struct(file_num).offsets_cumulative_original = flash_struct(file_num).offsets_cumulative;
        flash_struct(file_num).onsets_original = flash_struct(file_num).onsets;
        flash_struct(file_num).offsets_original = flash_struct(file_num).offsets;

        % Get the cumulative number of dropped frames for each drop event within this video
        num_dropped_cumulative = cumsum([flash_struct(file_num).drop_info.num_dropped]);

        % Loop over flash onsets
        for onset_idx = 1:length(flash_struct(file_num).onsets_cumulative)
            % Get the index of the most recent drop event before this flash onset
            previous_drop_idx = find([flash_struct(file_num).drop_info.frame_num] <= flash_struct(file_num).onsets(onset_idx), 1, 'last');
            if ~isempty(previous_drop_idx)
                % If there was a drop event before this flash onset (within this video), calculate the cumulative # of drops to adjust by
                drop_shift = num_dropped_cumulative(previous_drop_idx);
            else
                % No drops before this flash onset, zero adjustment
                drop_shift = 0;
            end
            % Calculate corrected onset frame using cumulative drops within this video, and cumulative drops in all previous videos
            flash_struct(file_num).onsets_cumulative(onset_idx) = flash_struct(file_num).onsets_cumulative(onset_idx) + drop_shift + cumulative_drops;
            flash_struct(file_num).offsets_cumulative(onset_idx) = flash_struct(file_num).offsets_cumulative(onset_idx) + drop_shift + cumulative_drops;
            flash_struct(file_num).onsets(onset_idx) = flash_struct(file_num).onsets(onset_idx) + drop_shift;
            flash_struct(file_num).offsets(onset_idx) = flash_struct(file_num).offsets(onset_idx) + drop_shift;
        end
        % Add on drops from this video to the overal cumulative drop count
        cumulative_drops = cumulative_drops + num_dropped_cumulative(end);
    else
        % No drops in this video, just adjust by number of cumulative drops from previous videos
        flash_struct(file_num).onsets_cumulative = flash_struct(file_num).onsets_cumulative + cumulative_drops;
        flash_struct(file_num).offsets_cumulative = flash_struct(file_num).offsets_cumulative + cumulative_drops;
    end
    flash_struct(file_num).num_frames = flash_struct(file_num).num_frames + num_dropped_cumulative(end);
end