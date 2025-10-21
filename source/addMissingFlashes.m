function flash_struct_corrected = addMissingFlashes(flash_struct, click_struct, options)
arguments
    flash_struct struct
    click_struct struct
    options.MinPossibleFPS = 20
    options.MaxPossibleFPS = 60
end

if length(unique([click_struct.fs])) > 1
    error('Multiple audio sampling rates found in this dataset.')
end

audio_fs = click_struct(1).fs;

audioToVideoScale = fuzzyMatchEvents( ...
    [click_struct.onsets_cumulative], ...
    [flash_struct.onsets_cumulative], ...
    audio_fs/options.MaxPossibleFPS, ...  % Min possible scale
    audio_fs/options.MinPossibleFPS ...  % Max possible scale
    );

click_period = mean(diff([click_struct.onsets_cumulative]));
average_fps = audio_fs / audioToVideoScale;
flash_period = click_period * (average_fps / audio_fs);

% Correct estimated flash_period
deltas = diff([flash_struct.onsets_cumulative]);
deviations = deltas - flash_period * round(deltas / flash_period);
flash_period_corrected = flash_period + mean(deviations);
fprintf('Initial flash period estimate: %.02f\n', flash_period);
fprintf('Corrected flash period:        %.02f\n', flash_period_corrected);
flash_period = flash_period_corrected;

flash_struct_corrected = flash_struct;

previous_flash_onset = flash_struct_corrected(1).onsets_cumulative(1);
previous_flash_offset = flash_struct_corrected(1).offsets_cumulative(1);

% Add missing flashes
for file_idx = 1:length(flash_struct_corrected)
    flash_struct_corrected(file_idx).missing = false(1, length(flash_struct_corrected(file_idx).onsets));
    onset_idx = 1;
    while true
        if onset_idx > length(flash_struct_corrected(file_idx).onsets)
            break;
        end
        flash_frame = flash_struct_corrected(file_idx).onsets_cumulative(onset_idx) - previous_flash_onset;
        num_missing_flashes = round((flash_frame) / flash_period) - 1;
        if num_missing_flashes > 0
            % At least one missing flash detected
            for m = 1:num_missing_flashes
                % Add the missing flashes one by one
                time_to_missing_flash = round(m * flash_period);
                missing_flash_frame_onset_cumulative = previous_flash_onset + time_to_missing_flash;
                [missing_file_idx, missing_file_first_frame, missing_flash_frame_onset] = which_file(flash_struct_corrected, missing_flash_frame_onset_cumulative);
                missing_flash_frame_offset_cumulative = previous_flash_offset + time_to_missing_flash;
                missing_flash_frame_offset = missing_flash_frame_offset_cumulative - missing_file_first_frame + 1;

                disp('*******************************')
                disp('Add missing flash:')
                disp(missing_flash_frame_onset_cumulative)
                disp('')
                if missing_file_idx > 1
                    disp('Previous file:')
                    disp(flash_struct_corrected(missing_file_idx - 1).onsets_cumulative);
                end
                disp('This file:')
                disp(flash_struct_corrected(missing_file_idx).onsets_cumulative)
                if missing_file_idx < length(flash_struct_corrected)
                    disp('Next file:')
                    disp(flash_struct_corrected(missing_file_idx + 1).onsets_cumulative);
                end
                disp('*******************************')
                

                % Insert missing flash
                flash_struct_corrected(missing_file_idx).onsets_cumulative = insertInArray(flash_struct_corrected(missing_file_idx).onsets_cumulative, onset_idx, missing_flash_frame_onset_cumulative);
                flash_struct_corrected(missing_file_idx).onsets = insertInArray(flash_struct_corrected(missing_file_idx).onsets, onset_idx, missing_flash_frame_onset);
                flash_struct_corrected(missing_file_idx).offsets_cumulative = insertInArray(flash_struct_corrected(missing_file_idx).offsets_cumulative, onset_idx, missing_flash_frame_offset_cumulative);
                flash_struct_corrected(missing_file_idx).offsets = insertInArray(flash_struct_corrected(missing_file_idx).offsets, onset_idx, missing_flash_frame_offset);
                flash_struct_corrected(missing_file_idx).missing = insertInArray(flash_struct_corrected(missing_file_idx).missing, onset_idx, true);
                % Adjust onset_idx to account for inserted flash
                onset_idx = onset_idx + 1;
                if onset_idx > length(flash_struct_corrected(file_idx).onsets)
                    break;
                end
            end
        end
        previous_flash_onset = flash_struct_corrected(file_idx).onsets_cumulative(onset_idx);
        previous_flash_offset = flash_struct_corrected(file_idx).offsets_cumulative(onset_idx);
        onset_idx = onset_idx + 1;
    end
end

function [file_idx, first_frame, onset_frame] = which_file(flash_struct, onset_frame_cumulative)
% Precompute 1-based first-frame index for each file: length N
starts = cumsum([1, flash_struct(1:end-1).num_frames]);
% Assign file where onset_frame_cumulative >= starts(k) and < starts(k)+num_frames(k)
file_idx = find(onset_frame_cumulative >= starts & ...
                onset_frame_cumulative <  (starts + [flash_struct.num_frames]), 1, 'first');
if isempty(file_idx)
    % clamp to last file if it lands exactly on the last boundary
    file_idx = numel(flash_struct);
end
first_frame = starts(file_idx);
onset_frame = onset_frame_cumulative - first_frame + 1;