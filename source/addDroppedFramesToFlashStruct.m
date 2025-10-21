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
for k = 1:length(flash_struct)
    % Construct expected dropped frame file path
    [directory, name, ~] = fileparts(flash_struct(k).path);
    dropped_frame_path = fullfile(directory, [name, '.txt']);
    % Check if there is a dropped frame file
    if exist(dropped_frame_path, "file")
        % Initialize dropped frame info struct for this video
        flash_struct(k).drop_info = struct();
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

                if isempty(missing_videos)
                    % Check if there seems to be missing files
                    missing_videos = 0;
                    num_samples_per_file = unique([flash_struct.num_frames]);
                    if ~isscalar(num_samples_per_file)
                        % Files do not all have same length
                        if min(num_samples_per_file) > frame_num
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
                flash_struct(k).drop_info(jj).frame_num = frame_num - flash_struct(k).num_frames * (k - 1 + missing_videos);
                flash_struct(k).drop_info(jj).frame_num_cumulative = frame_num - flash_struct(k).num_frames * missing_videos;
                flash_struct(k).drop_info(jj).frame_time = frame_time;
                flash_struct(k).drop_info(jj).last_ID = last_ID;
                flash_struct(k).drop_info(jj).this_ID = this_ID;
                flash_struct(k).drop_info(jj).num_dropped = num_dropped;
            end
        end

        % Create fields for drop-corrected onsets and offsets
        flash_struct(k).onsets_cumulative_original = flash_struct(k).onsets_cumulative;
        flash_struct(k).offsets_cumulative_original = flash_struct(k).offsets_cumulative;
        flash_struct(k).onsets_original = flash_struct(k).onsets;
        flash_struct(k).offsets_original = flash_struct(k).offsets;

        % Get the cumulative number of dropped frames for each drop event within this video
        num_dropped_cumulative = cumsum([flash_struct(k).drop_info.num_dropped]);

        fprintf('MISSING CORRECTION: **** Video %d\n', k);
        
        % Loop over flash onsets
        for onset_idx = 1:length(flash_struct(k).onsets_cumulative)
            % Get the index of the most recent drop event before this flash onset
            previous_drop_idx = find([flash_struct(k).drop_info.frame_num] <= flash_struct(k).onsets(onset_idx), 1, 'last');
            if ~isempty(previous_drop_idx)
                % If there was a drop event before this flash onset (within this video), calculate the cumulative # of drops to adjust by
                drop_shift = num_dropped_cumulative(previous_drop_idx);
            else
                % No drops before this flash onset, zero adjustment
                drop_shift = 0;
            end
            % Calculate corrected onset frame using cumulative drops within this video, and cumulative drops in all previous videos
            flash_struct(k).onsets_cumulative(onset_idx) = flash_struct(k).onsets_cumulative(onset_idx) + drop_shift + cumulative_drops;
            flash_struct(k).offsets_cumulative(onset_idx) = flash_struct(k).offsets_cumulative(onset_idx) + drop_shift + cumulative_drops;
            flash_struct(k).onsets(onset_idx) = flash_struct(k).onsets(onset_idx) + drop_shift;
            flash_struct(k).offsets(onset_idx) = flash_struct(k).offsets(onset_idx) + drop_shift;
            fprintf('MISSING CORRECTION: ** Onset_idx: %d\n', onset_idx);
            fprintf('MISSING CORRECTION: previous_drop_idx: %d\n', previous_drop_idx);
            fprintf('MISSING CORRECTION: drop_shift: %d\n', drop_shift);
            fprintf('MISSING CORRECTION: cumulative_drops: %d\n', cumulative_drops);
            fprintf('MISSING CORRECTION: onset correction: %d => %d\n', flash_struct(k).onsets_original(onset_idx), flash_struct(k).onsets(onset_idx));
            fprintf('MISSING CORRECTION: onset_cumulative correction: %d => %d\n', flash_struct(k).onsets_cumulative_original(onset_idx), flash_struct(k).onsets_cumulative(onset_idx));
        end
        % Add on drops from this video to the overal cumulative drop count
        cumulative_drops = cumulative_drops + num_dropped_cumulative(end);
    else
        % No drops in this video, just adjust by number of cumulative drops from previous videos
        flash_struct(k).onsets_cumulative = flash_struct(k).onsets_cumulative + cumulative_drops;
        flash_struct(k).offsets_cumulative = flash_struct(k).offsets_cumulative + cumulative_drops;
    end
    flash_struct(k).num_frames = flash_struct(k).num_frames + num_dropped_cumulative(end);
end