function [sync_struct, click_struct, naneye_flash_struct, webcam_flash_struct] = ...
    getPupillometryDataAlignment(root, options)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% getPupillometryDataAlignment: Extract synchronization info from data
% usage: [sync_struct, click_struct, naneye_flash_struct, 
%   webcam_flash_struct] = getPupillometryDataAlignment(root, options)
%
% where,
%    root is the root folder in which to look for audio and video files
%    Name/Value options can include:
%       ClickStruct: A previously created click_struct, if you want to 
%           avoid recalculating it. Default is [], meaning a new one will 
%           be created
%       NaneyeFlashStruct A previously created naneye_flash_struct, if you 
%           want to avoid recalculating it. Default is [], meaning a new 
%           one will be created
%       WebcamFlashStruct = A previously created webcam_flahs_struct, if 
%           you want to avoid recalculating it. Default is [], meaning a 
%           new one will be created
%       NaneyeNumIgnoredPulses: Number of initial naneye sync pulses to
%           ignore. Use this if the naneye camera recorded one or more sync
%           pulses at the beginning of a session that the webcam and 
%           microphone did not start soon enough to capture. Default is 0
%       WebcamNumIgnoredPulses = Number of initial webcam sync pulses to
%           ignore. Use this if the webcam camera recorded one or more sync
%           pulses at the beginning of a session that the naneye and 
%           microphone did not start soon enough to capture. Default is 0
%       AudioNumIgnoredPulses = Number of initial audio sync pulses to
%           ignore. Use this if the microphone recorded one or more sync
%           pulses at the beginning of a session that the webcam and 
%           naneye did not start soon enough to capture. Default is 0
%    sync_struct is a structure containing comprehensive synchronization
%       information about the three data streams. Can be used by 
%       alignVideosToAudio
%    click_struct contains the intermediate audio-only sync info
%    naneye_flash_struct contains the intermediate naneye-only sync info
%    webcam_flash_struct contains the intermediate webcam-only sync info
%
% This function takes three un-aligned streams - audio, webcam, and naneye,
%   and uses a common sync signal (simultaneous flashes and clicks) to
%   detect how the three streams are aligned. The main output is the
%   sync_struct, which can be passed to alignVideosToAudio to execute the
%   post-hoc alignment of the three data streams
%
% See also: alignVideosToAudio
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
arguments
    root
    options.ClickStruct = []
    options.NaneyeFlashStruct = []
    options.WebcamFlashStruct = []
    options.NaneyeNumIgnoredPulses = 0
    options.WebcamNumIgnoredPulses = 0
    options.AudioNumIgnoredPulses = 0
end

click_struct = options.ClickStruct;
naneye_flash_struct = options.NaneyeFlashStruct;
webcam_flash_struct = options.WebcamFlashStruct;

if isempty(click_struct)
    disp('Finding audio clicks...')
    click_struct = makeAudioSyncStruct( ...
        root, ...
        0.015, ...
        0.08, ...
        "Channel", 1, ...
        "NumIgnoredClicks", ...
        options.AudioNumIgnoredPulses ...
        );
    disp('...done')
end

if isempty(naneye_flash_struct)
    disp('finding naneye flashes...')
    naneye_flash_struct = makeVideoSyncStruct( ...
        root, ...
        [200, 1, 50, 50], ...
        0.5, ...
        0.08, ...
        'FrameRate', 48, ...
        'FileRegex', '_naneye.*\.avi', ...
        'MedianWindow', 20, ...
        'RangeBasedThreshold', true, ...
        'PlotOnsets', false, ...
        'NumIgnoredFlashes', options.NaneyeNumIgnoredPulses ...
        );
    disp('...done')
    naneye_flash_struct = addDroppedFramesToFlashStruct(naneye_flash_struct, 256);
    naneye_flash_struct = cullSpuriousFlashes(naneye_flash_struct, click_struct);
    naneye_flash_struct = addMissingFlashes(naneye_flash_struct, click_struct);
end

if isempty(webcam_flash_struct)
    disp('finding webcam flashes...')
    webcam_flash_struct = makeVideoSyncStruct( ...
        root, ...
        [1, 1, 50, 50], ...
        175, ...
        0.08, ...
        'FrameRate', 45, ...
        'FileRegex', '_camera.*\.avi', ...
        'PlotOnsets', false, ...
        'NumIgnoredFlashes', options.WebcamNumIgnoredPulses ...
        );
    disp('...done')
    webcam_flash_struct = cullSpuriousFlashes(webcam_flash_struct, click_struct);
    webcam_flash_struct = addMissingFlashes(webcam_flash_struct, click_struct);
end

sync_struct = struct();

% Get sync click registration
sync_count = 1;
file_start_sample = 1;
for file_idx = 1:length(click_struct)
    if file_idx > 1
        file_start_sample = file_start_sample + click_struct(file_idx-1).num_samples;
    end
    for onset_idx = 1:length(click_struct(file_idx).onsets)
        sync_struct(sync_count).pulse_idx = sync_count;
        sync_struct(sync_count).pulse_time = click_struct(file_idx).onsets_cumulative(onset_idx) / click_struct(file_idx).fs;
        sync_struct(sync_count).audio_file = click_struct(file_idx).path;
        sync_struct(sync_count).audio_file_idx = file_idx;
        sync_struct(sync_count).audio_file_start_sample = file_start_sample;
        sync_struct(sync_count).audio_fs = click_struct(file_idx).fs;
        sync_struct(sync_count).audio_num_samples = click_struct(file_idx).num_samples;
        sync_struct(sync_count).click_idx = onset_idx;
        sync_struct(sync_count).click_onset = click_struct(file_idx).onsets(onset_idx);
        sync_struct(sync_count).click_onset_cumulative = click_struct(file_idx).onsets_cumulative(onset_idx);
        sync_count = sync_count + 1;
    end
end
num_audio_clicks = sync_count;

% Add naneye flash registration
sync_count = 1;
file_start_sample = 1;
for file_idx = 1:length(naneye_flash_struct)
    if file_idx > 1
        file_start_sample = file_start_sample + naneye_flash_struct(file_idx-1).num_frames;
    end
    for onset_idx = 1:length(naneye_flash_struct(file_idx).onsets)
        sync_struct(sync_count).naneye_file = naneye_flash_struct(file_idx).path;
        sync_struct(sync_count).naneye_file_idx = file_idx;
        sync_struct(sync_count).naneye_file_start_sample = file_start_sample;
        sync_struct(sync_count).naneye_flash_onset = naneye_flash_struct(file_idx).onsets(onset_idx);
        sync_struct(sync_count).naneye_flash_onset_cumulative = naneye_flash_struct(file_idx).onsets_cumulative(onset_idx);
        sync_struct(sync_count).naneye_num_frames = naneye_flash_struct(file_idx).num_frames;
        sync_struct(sync_count).naneye_missing = naneye_flash_struct(file_idx).missing(onset_idx);
        sync_struct(sync_count).naneye_drop_info = naneye_flash_struct(file_idx).drop_info;  % This will sometimes be repeated, but it's ok
        sync_count = sync_count + 1;
        if sync_count >= num_audio_clicks
            break;
        end
    end
    if sync_count >= num_audio_clicks
        break;
    end
end

% Add webcam flash registration
sync_count = 1;
file_start_sample = 1;
for file_idx = 1:length(webcam_flash_struct)
    if file_idx > 1
        file_start_sample = file_start_sample + webcam_flash_struct(file_idx-1).num_frames;
    end
    for onset_idx = 1:length(webcam_flash_struct(file_idx).onsets)
        sync_struct(sync_count).webcam_file = webcam_flash_struct(file_idx).path;
        sync_struct(sync_count).webcam_file_idx = file_idx;
        sync_struct(sync_count).webcam_file_start_sample = file_start_sample;
        sync_struct(sync_count).webcam_flash_onset = webcam_flash_struct(file_idx).onsets(onset_idx);
        sync_struct(sync_count).webcam_flash_onset_cumulative = webcam_flash_struct(file_idx).onsets_cumulative(onset_idx);
        sync_struct(sync_count).webcam_num_frames = webcam_flash_struct(file_idx).num_frames;
        sync_struct(sync_count).webcam_missing = webcam_flash_struct(file_idx).missing(onset_idx);
        sync_count = sync_count + 1;
        if sync_count >= num_audio_clicks
            break;
        end
    end
    if sync_count >= num_audio_clicks
        break;
    end
end

% Cut sync struct down to smallest data set length
num_clicks = [sync_struct.audio_file_idx];
num_naneye_flashes = [sync_struct.naneye_file_idx];
num_webcam_flashes = [sync_struct.webcam_file_idx];
num_sync_pulses = min([num_clicks, num_naneye_flashes, num_webcam_flashes]);
sync_struct = sync_struct(1:num_sync_pulses);

% Calculate instantaneous webcam and naneye frame rates based on inter pulse intervals
for pulse_idx = 1:length(sync_struct)

    this_pulse_time = sync_struct(pulse_idx).pulse_time;
    this_naneye_sample = sync_struct(pulse_idx).naneye_flash_onset_cumulative;
    this_webcam_sample = sync_struct(pulse_idx).webcam_flash_onset_cumulative;

    if pulse_idx > 1
        prev_pulse_time = sync_struct(pulse_idx-1).pulse_time;
        prev_naneye_sample = sync_struct(pulse_idx-1).naneye_flash_onset_cumulative;
        prev_webcam_sample = sync_struct(pulse_idx-1).webcam_flash_onset_cumulative;

        prev_dt = this_pulse_time - prev_pulse_time;

        prev_naneye_fs = (this_naneye_sample - prev_naneye_sample) / prev_dt;
        prev_webcam_fs = (this_webcam_sample - prev_webcam_sample) / prev_dt;
    else
        prev_naneye_fs = nan;
        prev_webcam_fs = nan;
    end

    if pulse_idx < length(sync_struct)
        next_pulse_time = sync_struct(pulse_idx+1).pulse_time;
        next_naneye_sample = sync_struct(pulse_idx+1).naneye_flash_onset_cumulative;
        next_webcam_sample = sync_struct(pulse_idx+1).webcam_flash_onset_cumulative;

        next_dt = next_pulse_time - this_pulse_time;

        next_naneye_fs = (next_naneye_sample - this_naneye_sample) / next_dt;
        next_webcam_fs = (next_webcam_sample - this_webcam_sample) / next_dt;
    else
        next_naneye_fs = nan;
        next_webcam_fs = nan;
    end

    if isnan(prev_naneye_fs) || isnan(next_naneye_fs)
        if isnan(prev_naneye_fs) && isnan(next_naneye_fs)
            error('Could not calculate any frame rate for pulse #%d', pulse_idx);
        end
        if isnan(prev_naneye_fs)
            % No previous value
            sync_struct(pulse_idx).naneye_fs = next_naneye_fs;
            sync_struct(pulse_idx).webcam_fs = next_webcam_fs;

            sync_struct(pulse_idx).naneye_fs_variation = nan;
            sync_struct(pulse_idx).webcam_fs_variation = nan;
        elseif isnan(next_naneye_fs)
            % No next value
            sync_struct(pulse_idx).naneye_fs = prev_naneye_fs;
            sync_struct(pulse_idx).webcam_fs = prev_webcam_fs;

            sync_struct(pulse_idx).naneye_fs_variation = nan;
            sync_struct(pulse_idx).webcam_fs_variation = nan;
        end
    else
        % Both values present
        sync_struct(pulse_idx).naneye_fs = mean([prev_naneye_fs, next_naneye_fs]);
        sync_struct(pulse_idx).webcam_fs = mean([prev_webcam_fs, next_webcam_fs]);

        sync_struct(pulse_idx).naneye_fs_variation = abs(prev_naneye_fs - next_naneye_fs);
        sync_struct(pulse_idx).webcam_fs_variation = abs(prev_webcam_fs - next_webcam_fs);
    end

end