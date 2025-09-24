%function alignment = getPupillometryDataAlignment(root)

if ~exist("click_struct", 'var')
    disp('Finding audio clicks...')
    click_struct = makeAudioSyncStruct(root, 0.03, 0.08, "Channel", 1);
    disp('...done')
end

if ~exist("naneye_flash_struct", 'var')
    disp('finding naneye flashes...')
    naneye_flash_struct = makeVideoSyncStruct( ...
        root, ...
        [1, 260, 40, 40], ...
        10, ...
        0.08, ...
        'FrameRate', 48, ...
        'FileRegex', '_naneye.*\.avi', ...
        'MedianWindow', 20, ...
        'PlotOnsets', false ...
        );
    disp('...done')
end

if ~exist("webcam_flash_struct", 'var')
    disp('finding webcam flashes...')
    webcam_flash_struct = makeVideoSyncStruct( ...
        root, ...
        [1, 1, 10, 10], ...
        175, ...
        0.08, ...
        'FrameRate', 45, ...
        'FileRegex', '_camera.*\.avi', ...
        'PlotOnsets', false ...
        );
    disp('...done')
end

sync_struct = struct();
sync_count = 0;
cumulative_samples = 0;

if length(unique([click_struct.fs])) > 1
    error('Multiple audio sampling rates found in this dataset.')
end

audio_fs = click_struct(1).fs;

min_possible_naneye_fps = 20;
max_possible_naneye_fps = 60;

audioToNaneyeScale = fuzzyMatchEvents( ...
    [click_struct.onsets_cumulative], ...
    [naneye_flash_struct.onsets_cumulative], ...
    audio_fs/max_possible_naneye_fps, ...  % Min possible scale
    audio_fs/min_possible_naneye_fps ...  % Max possible scale
    );

click_period = mean(diff([click_struct.onsets_cumulative]));
average_naneye_fps = audio_fs / audioToNaneyeScale;
average_naneye_period = 1/average_naneye_fps;
max_naneye_deviation = click_period * (average_naneye_fps / audio_fs)* 0.08;
first_naneye_flash = naneye_flash_struct(1).onsets_cumulative(1);

naneye_flash_struct_corrected = naneye_flash_struct;
% Reconstruct theoretical naneye flash times
for file_idx = 1:length(naneye_flash_struct_corrected)
    invalid_flash_idx = [];
    for onset_idx = 1:length(naneye_flash_struct_corrected(file_idx).onsets)
        flash_frame = naneye_flash_struct_corrected(file_idx).onsets_cumulative(onset_idx) - first_naneye_flash
        corrected_flash_frame = average_naneye_period * round((flash_frame) / average_naneye_period)
        % Is corrected flash frame close, or is this a spurious flash
        if abs(flash_frame - corrected_flash_frame) > max_naneye_deviation
            fprintf('deviation is %f, it is not real!\n', abs(flash_frame - corrected_flash_frame))
            invalid_flash_idx(end+1) = onset_idx;
        end
    end
    naneye_flash_struct_corrected(file_idx).onsets(invalid_flash_idx) = [];
    naneye_flash_struct_corrected(file_idx).offsets(invalid_flash_idx) = [];
    naneye_flash_struct_corrected(file_idx).onsets_cumulative(invalid_flash_idx) = [];
    naneye_flash_struct_corrected(file_idx).offsets_cumulative(invalid_flash_idx) = [];
end


% Get sync/click registration
for audio_file_idx = 1:length(click_struct)
    for onset_num = 1:length(click_struct(audio_file_idx).onsets)
        sync_count = sync_count + 1;
        sync_struct(sync_count).audio_file = click_struct(audio_file_idx).path;
        sync_struct(sync_count).pulse_idx = onset_num;
        sync_struct(sync_count).pulse_onset = click_struct(audio_file_idx).onsets(onset_num);
        sync_struct(sync_count).pulse_onset_cumulative = click_struct(audio_file_idx).onsets(onset_num) + cumulative_samples;
        % Find corresponding webcam sync pulses

    end
    cumulative_samples = cumulative_samples + click_struct(audio_file_idx).num_samples;
end