function alignVideosToAudio(sync_struct, aligned_folder)

% Get a list of all audio paths
audio_paths = sort(unique({sync_struct.audio_file}));

% Initialize a structure holding the information about what to actually do to the videos
naneye_job_struct = struct();
webcam_job_struct = struct();

% Loop over audio files
for output_file_idx = 1:length(audio_paths)
    % Current audio file path
    audio_path = audio_paths{output_file_idx};

    % Determine which pulses occur in this audio file
    pulse_idx = find(strcmp(audio_path, {sync_struct.audio_file}));
    if any(diff(pulse_idx) ~= 1)
        error('something is wrong with audio file path order in sync_struct')
    end

    % Get sync sub-struct for first pulse in this audio file
    first_pulse = sync_struct(pulse_idx(1));

    % Get the offset in seconds between the start of the audio file and the first pulse
    first_pulse_offset_time = first_pulse.pulse_time - first_pulse.audio_file_start_sample / first_pulse.audio_fs;

    % Get cumulative sample (frame) that corresponds to the start of the audio file
    naneye_start_sample = round(first_pulse.naneye_flash_onset_cumulative - first_pulse_offset_time * first_pulse.naneye_fs);
    webcam_start_sample = round(first_pulse.webcam_flash_onset_cumulative - first_pulse_offset_time * first_pulse.webcam_fs);

    % Determine # of video samples (frames) that occur during this audio file
    naneye_num_samples = first_pulse.naneye_fs * first_pulse.audio_num_samples / first_pulse.audio_fs;
    webcam_num_samples = first_pulse.webcam_fs * first_pulse.audio_num_samples / first_pulse.audio_fs;

    % Get cumulative sample (frame) that corresponds to the end of the audio file
    naneye_end_sample = naneye_start_sample + naneye_num_samples - 1;
    webcam_end_sample = webcam_start_sample + webcam_num_samples - 1;

    % Find sync index for the video files that contain the beginning of the audio file
    naneye_start_idx = find([sync_struct.naneye_file_start_sample] <= naneye_start_sample, 1, "last");
    webcam_start_idx = find([sync_struct.webcam_file_start_sample] <= webcam_start_sample, 1, "last");

    % Find sync index for the video files that contain the end of the audio file
    naneye_end_idx = find([sync_struct.naneye_file_start_sample] <= naneye_start_sample + naneye_num_samples, 1, "last");
    webcam_end_idx = find([sync_struct.webcam_file_start_sample] <= webcam_start_sample + webcam_num_samples, 1, "last");

    % Construct the range of sync indices covering the audio file for 
    naneye_idx_range = naneye_start_idx:naneye_end_idx;
    webcam_idx_range = webcam_start_idx:webcam_end_idx;

    % Set up the job parameters
    % Set up the job parameters
    naneye_job_struct(output_file_idx).files = sort(unique({sync_struct(naneye_idx_range).naneye_file}));
    naneye_job_struct(output_file_idx).fs = mean([sync_struct(naneye_idx_range).naneye_fs]);
    naneye_job_struct(output_file_idx).delta_fs = max([sync_struct(naneye_idx_range).naneye_fs_variation], [], 'omitnan');
    naneye_job_struct(output_file_idx).first_file_start_frame = naneye_start_sample - sync_struct(naneye_start_idx).naneye_file_start_sample + 1;
    naneye_job_struct(output_file_idx).last_file_end_frame =    naneye_end_sample - sync_struct(naneye_end_idx).naneye_file_start_sample + 1;

    % Set up the job parameters
    webcam_job_struct(output_file_idx).files = sort(unique({sync_struct(webcam_idx_range).webcam_file}));
    webcam_job_struct(output_file_idx).fs = mean([sync_struct(webcam_idx_range).webcam_fs]);
    webcam_job_struct(output_file_idx).delta_fs = max([sync_struct(webcam_idx_range).webcam_fs_variation], [], 'omitnan');
    webcam_job_struct(output_file_idx).first_file_start_frame = webcam_start_sample - sync_struct(webcam_start_idx).webcam_file_start_sample + 1;
    webcam_job_struct(output_file_idx).last_file_end_frame =    webcam_end_sample - sync_struct(webcam_end_idx).webcam_file_start_sample + 1;
end

file_cache = containers.Map();

for output_file_idx = 1:length(naneye_job_struct)
    for source_file_idx = 1:length(naneye_job_struct(output_file_idx).files)
        source_file_path = naneye_job_struct(output_file_idx).files{source_file_idx};
        if file_cache.isKey(source_file_path)
            % We've already loaded this file, get data from cache
            video_data = file_cache(source_file_path);
        else
            % New file, load it and cache it
            video_data = loadVideoData(source_file_path);
            file_cache(source_file_path) = video_data;
        end
        

    end
end
