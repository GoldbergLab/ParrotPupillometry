function flash_struct_corrected = cullSpuriousFlashes(flash_struct, click_struct, options)
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
fprintf('Initial flash period estimate: %d\n', flash_period);
fprintf('Corrected flash period:        %f\n', flash_period_corrected);
flash_period = flash_period_corrected;

max_deviation = flash_period * 0.15;
last_flash = flash_struct(1).onsets_cumulative(1);

flash_struct_corrected = flash_struct;
% Reconstruct theoretical video flash times
for file_idx = 1:length(flash_struct_corrected)
    invalid_flash_idx = [];
    for onset_idx = 1:length(flash_struct_corrected(file_idx).onsets)
        flash_frame = flash_struct_corrected(file_idx).onsets_cumulative(onset_idx) - last_flash;
        corrected_flash_frame = flash_period * round((flash_frame) / flash_period);
        fprintf('%f ==> %.01f == %dth flash (%f)\n', flash_frame, corrected_flash_frame, round((flash_frame) / flash_period), abs(flash_frame - corrected_flash_frame));
        % Is corrected flash frame close, or is this a spurious flash
        if abs(flash_frame - corrected_flash_frame) > max_deviation
            fprintf('deviation is %f, it is not real!\n', abs(flash_frame - corrected_flash_frame))
            invalid_flash_idx(end+1) = onset_idx;
        else
            last_flash = flash_struct_corrected(file_idx).onsets_cumulative(onset_idx);
        end
            
    end
    flash_struct_corrected(file_idx).onsets(invalid_flash_idx) = [];
    flash_struct_corrected(file_idx).offsets(invalid_flash_idx) = [];
    flash_struct_corrected(file_idx).onsets_cumulative(invalid_flash_idx) = [];
    flash_struct_corrected(file_idx).offsets_cumulative(invalid_flash_idx) = [];
end