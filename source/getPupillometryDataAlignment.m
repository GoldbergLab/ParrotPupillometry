function [sync_struct, click_struct, naneye_flash_struct, webcam_flash_struct] = getPupillometryDataAlignment(root, options)
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
%       SaveStructs = Whether or not to save the synchronization structs
%           to disk in case of a crash or for later use or posterity or 
%           whatever. Default is true.
%       FileLimit = The number of files to limit each data stream to.
%           Typical use case is if you just want to test alignment on the 
%           first few files. Default is [], meaning all files are processed
%       ClickChannel = Audio channel # containing the sync clicks. Default
%           is 1.
%       NaneyeBadSyncFileIdx, WebcamBadSyncFileIdx, AudioBadSyncFileIdx = 
%           A list of file indices for each stream in which the sync
%           signal is absent or otherwise unusable. The videos will be
%           included in the final alignment, but they will not be analyzed
%           to find the sync signal. Interpolation will be used to fill in
%           the missing flash/click data. Default is [].
%       IncludeNaneye = whether or not to look for/use naneye data. Default
%           is true.
%       IncludeWebcam = whether or not to look for/use webcam data. Default
%           is true.
%       DualNaneyeSync = whether the stacked naneye video contains a sync
%           flash in BOTH halves (one per camera), so the two eyes can be
%           synced independently. When true (default), the top and bottom
%           halves are treated as two independent streams, each cut against
%           its own flash. When false, a single flash is used and both
%           halves are cut together (legacy behavior, for data acquired with
%           a sync LED pointed at only one camera).
%       NaneyeEyeHeight = height in pixels of a single naneye eye (one half
%           of the stacked frame). Used to derive the default per-eye flash
%           ROIs and source rows. Default is 250.
%       NaneyeROI, NaneyeNumIgnoredPulses, NaneyeBadSyncFileIdx may be given
%           per-eye when DualNaneyeSync is true: an Nx4 ROI matrix, a vector
%           of ignored-pulse counts, and a cell array of bad-sync file lists
%           respectively (one entry per eye). A single/scalar value is
%           broadcast to every eye.
%    sync_struct is a structure containing comprehensive synchronization
%       information about the data streams, with one element per sync pulse
%       and nested per-stream fields (sync_struct.audio.*, .webcam.*, and the
%       struct array .naneye(s).* with one entry per naneye eye). Can be used
%       by alignVideosToAudio
%    click_struct contains the intermediate audio-only sync info
%    naneye_flash_struct is a cell array containing the intermediate
%       naneye-only sync info, one flash struct per eye
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
    options.SaveStructs = true
    options.FileLimit = []
    options.ClickChannel = 1
    options.NaneyeBadSyncFileIdx = []
    options.WebcamBadSyncFileIdx = []
    options.AudioBadSyncFileIdx = []
    options.WebcamROI = [1, 1, 50, 50]
    options.NaneyeROI = []
    options.IncludeNaneye = true
    options.IncludeWebcam = true
    options.DualNaneyeSync = true
    options.NaneyeEyeHeight = 250
end

% Build the naneye sub-stream configuration. Each entry is one independently-
%   synced "eye". With DualNaneyeSync == false there is a single sub-stream that
%   reproduces the legacy behavior (one flash, both stacked halves cut together).
%   With DualNaneyeSync == true there are two sub-streams - one per stacked half -
%   each with its own flash ROI, ignored-pulse count, bad-sync file list, and
%   the source rows it occupies in the stacked frame.
eye_height = options.NaneyeEyeHeight;
if options.DualNaneyeSync
    num_naneye_streams = 2;
    default_roi = [200, 1, 50, 50; 200, eye_height + 1, 50, 50];
    naneye_src_rows = {1:eye_height, (eye_height + 1):(2 * eye_height)};
    naneye_labels = {'eye0', 'eye1'};
else
    num_naneye_streams = 1;
    default_roi = [200, 1, 50, 50];
    naneye_src_rows = {[]};  % [] => legacy whole-frame destack in alignVideosToAudio
    naneye_labels = {'naneye'};
end

% Per-eye flash ROI (Nx4). Empty => built-in defaults above.
if isempty(options.NaneyeROI)
    naneye_roi = default_roi;
else
    naneye_roi = options.NaneyeROI;
    if size(naneye_roi, 1) == 1 && num_naneye_streams > 1
        error(['NaneyeROI must have one row per naneye sub-stream (%d) when ' ...
            'DualNaneyeSync is true; got a single row.'], num_naneye_streams);
    end
    if size(naneye_roi, 1) ~= num_naneye_streams
        error('NaneyeROI must have %d row(s), got %d.', num_naneye_streams, size(naneye_roi, 1));
    end
end

% Per-eye ignored-pulse count: a scalar broadcasts to all eyes, otherwise supply
%   one element per eye.
naneye_num_ignored = options.NaneyeNumIgnoredPulses;
if isscalar(naneye_num_ignored)
    naneye_num_ignored = repmat(naneye_num_ignored, 1, num_naneye_streams);
elseif numel(naneye_num_ignored) ~= num_naneye_streams
    error('NaneyeNumIgnoredPulses must be a scalar or have %d elements.', num_naneye_streams);
end

% Per-eye bad-sync file indices: a plain list broadcasts to all eyes; a cell
%   array with one entry per eye sets each eye independently.
naneye_bad_sync = options.NaneyeBadSyncFileIdx;
if ~iscell(naneye_bad_sync)
    naneye_bad_sync = repmat({naneye_bad_sync}, 1, num_naneye_streams);
elseif numel(naneye_bad_sync) ~= num_naneye_streams
    error('NaneyeBadSyncFileIdx must be a plain list or a 1x%d cell array.', num_naneye_streams);
end

sync_struct = struct();
click_struct = options.ClickStruct;
naneye_flash_struct = options.NaneyeFlashStruct;
% naneye_flash_struct is a cell array with one flash struct per eye. Accept a
%   plain flash struct (e.g. a precomputed single-eye struct) for convenience.
if ~isempty(naneye_flash_struct) && ~iscell(naneye_flash_struct)
    naneye_flash_struct = {naneye_flash_struct};
end
webcam_flash_struct = options.WebcamFlashStruct;
analysis_date = char(datetime());
if options.SaveStructs
    structFile = getAlignmentStructPath(root);
    save(structFile, 'click_struct', 'naneye_flash_struct', 'webcam_flash_struct', 'sync_struct', 'analysis_date');
end

if isempty(click_struct)
    disp('Finding audio clicks...')
    click_struct = makeAudioSyncStruct( ...
        root, ...
        0.01, ...
        0.08, ...
        "Channel", options.ClickChannel, ...
        "NumIgnoredClicks", options.AudioNumIgnoredPulses, ...
        "FileLimit", options.FileLimit, ...
        "BadSyncFileIdx", options.AudioBadSyncFileIdx, ...
        'PlotOnsets', false ...
        );
    disp('...done')
    if options.SaveStructs
        save(structFile, 'click_struct', '-append');
    end
end

if isempty(naneye_flash_struct) && options.IncludeNaneye
    % One flash struct per naneye sub-stream (eye). Each eye is detected, drop-
    %   corrected, and culled/back-filled against the shared click_struct
    %   independently, so each is registered to the same audio master clock
    %   regardless of the (unsynced) offset between the two cameras.
    naneye_flash_struct = cell(1, num_naneye_streams);
    for s = 1:num_naneye_streams
        fprintf('finding naneye flashes for %s...\n', naneye_labels{s})
        flash_struct = makeVideoSyncStruct( ...
            root, ...
            naneye_roi(s, :), ...
            0.5, ...
            0.08, ...
            'FrameRate', 48, ...
            'FileRegex', '_naneye.*\.avi', ...
            'MedianWindow', 20, ...
            'RangeBasedThreshold', true, ...
            'PlotOnsets', false, ...
            'NumIgnoredFlashes', naneye_num_ignored(s), ...
            "FileLimit", options.FileLimit, ...
            "BadSyncFileIdx", naneye_bad_sync{s} ...
            );
        flash_struct = addDroppedFramesToFlashStruct(flash_struct, 256);
        flash_struct = cullSpuriousFlashes(flash_struct, click_struct);
        flash_struct = addMissingFlashes(flash_struct, click_struct);
        naneye_flash_struct{s} = flash_struct;
    end
    disp('...done')
    if options.SaveStructs
        save(structFile, 'naneye_flash_struct', '-append');
    end
end

if isempty(webcam_flash_struct) && options.IncludeWebcam
    disp('finding webcam flashes...')
    webcam_flash_struct = makeVideoSyncStruct( ...
        root, ...
        options.WebcamROI, ...
        175, ...
        0.08, ...
        'FrameRate', 45, ...
        'FileRegex', '_camera.*\.avi', ...
        'PlotOnsets', false, ...
        'NumIgnoredFlashes', options.WebcamNumIgnoredPulses, ...
        "FileLimit", options.FileLimit, ...
        "BadSyncFileIdx", options.WebcamBadSyncFileIdx ...
        );
    disp('...done')
    webcam_flash_struct = cullSpuriousFlashes(webcam_flash_struct, click_struct);
    webcam_flash_struct = addMissingFlashes(webcam_flash_struct, click_struct);
    if options.SaveStructs
        save(structFile, 'webcam_flash_struct', '-append');
    end
end

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
        sync_struct(sync_count).audio = struct( ...
            'file', click_struct(file_idx).path, ...
            'file_idx', file_idx, ...
            'file_start_sample', file_start_sample, ...
            'fs', click_struct(file_idx).fs, ...
            'num_samples', click_struct(file_idx).num_samples, ...
            'click_idx', onset_idx, ...
            'click_onset', click_struct(file_idx).onsets(onset_idx), ...
            'click_onset_cumulative', click_struct(file_idx).onsets_cumulative(onset_idx));
        sync_count = sync_count + 1;
    end
end
num_audio_clicks = sync_count;

% Add naneye flash registration. Each sub-stream (eye) is registered into the
%   same pulse rows under sync_struct(row).naneye(s), but with its own flash
%   onsets, so the two halves end up cut independently downstream.
naneye_stream_counts = zeros(1, num_naneye_streams);
if options.IncludeNaneye
    for s = 1:num_naneye_streams
        flash_struct = naneye_flash_struct{s};
        sync_count = 1;
        file_start_sample = 1;
        for file_idx = 1:length(flash_struct)
            if file_idx > 1
                file_start_sample = file_start_sample + flash_struct(file_idx-1).num_frames;
            end
            for onset_idx = 1:length(flash_struct(file_idx).onsets)
                sync_struct(sync_count).naneye(s).label = naneye_labels{s};
                sync_struct(sync_count).naneye(s).src_rows = naneye_src_rows{s};
                sync_struct(sync_count).naneye(s).file = flash_struct(file_idx).path;
                sync_struct(sync_count).naneye(s).file_idx = file_idx;
                sync_struct(sync_count).naneye(s).file_start_sample = file_start_sample;
                sync_struct(sync_count).naneye(s).flash_onset = flash_struct(file_idx).onsets(onset_idx);
                sync_struct(sync_count).naneye(s).flash_onset_cumulative = flash_struct(file_idx).onsets_cumulative(onset_idx);
                sync_struct(sync_count).naneye(s).num_frames = flash_struct(file_idx).num_frames;
                sync_struct(sync_count).naneye(s).missing = flash_struct(file_idx).missing(onset_idx);
                sync_struct(sync_count).naneye(s).drop_info = flash_struct(file_idx).drop_info;  % This will sometimes be repeated, but it's ok
                sync_count = sync_count + 1;
                if sync_count >= num_audio_clicks
                    break;
                end
            end
            if sync_count >= num_audio_clicks
                break;
            end
        end
        naneye_stream_counts(s) = sync_count - 1;
    end
end

% Add webcam flash registration
if options.IncludeWebcam
    sync_count = 1;
    file_start_sample = 1;
    for file_idx = 1:length(webcam_flash_struct)
        if file_idx > 1
            file_start_sample = file_start_sample + webcam_flash_struct(file_idx-1).num_frames;
        end
        for onset_idx = 1:length(webcam_flash_struct(file_idx).onsets)
            sync_struct(sync_count).webcam = struct( ...
                'file', webcam_flash_struct(file_idx).path, ...
                'file_idx', file_idx, ...
                'file_start_sample', file_start_sample, ...
                'flash_onset', webcam_flash_struct(file_idx).onsets(onset_idx), ...
                'flash_onset_cumulative', webcam_flash_struct(file_idx).onsets_cumulative(onset_idx), ...
                'num_frames', webcam_flash_struct(file_idx).num_frames, ...
                'missing', webcam_flash_struct(file_idx).missing(onset_idx));
            sync_count = sync_count + 1;
            if sync_count >= num_audio_clicks
                break;
            end
        end
        if sync_count >= num_audio_clicks
            break;
        end
    end
    webcam_count = sync_count - 1;
end

% Cut sync struct down to smallest data set length. For naneye, every eye must
%   have a registered flash for a pulse to be usable, so we take the smallest
%   count across eyes.
num_clicks = num_audio_clicks - 1;
if options.IncludeNaneye
    num_naneye_flashes = min(naneye_stream_counts);
else
    num_naneye_flashes = nan;
end
if options.IncludeWebcam
    num_webcam_flashes = webcam_count;
else
    num_webcam_flashes = nan;
end
num_sync_pulses = min([num_clicks, num_naneye_flashes, num_webcam_flashes]);
sync_struct = sync_struct(1:num_sync_pulses);

% Calculate instantaneous frame rate for each video stream based on inter-pulse
%   intervals. Each naneye eye is computed independently from its own flashes.
pulse_times = [sync_struct.pulse_time];

if options.IncludeNaneye
    for s = 1:num_naneye_streams
        onset_cumulative = arrayfun(@(row) row.naneye(s).flash_onset_cumulative, sync_struct);
        [fs, fs_variation] = computeInterPulseFrameRate(pulse_times, onset_cumulative);
        for pulse_idx = 1:length(sync_struct)
            sync_struct(pulse_idx).naneye(s).fs = fs(pulse_idx);
            sync_struct(pulse_idx).naneye(s).fs_variation = fs_variation(pulse_idx);
        end
    end
end

if options.IncludeWebcam
    onset_cumulative = arrayfun(@(row) row.webcam.flash_onset_cumulative, sync_struct);
    [fs, fs_variation] = computeInterPulseFrameRate(pulse_times, onset_cumulative);
    for pulse_idx = 1:length(sync_struct)
        sync_struct(pulse_idx).webcam.fs = fs(pulse_idx);
        sync_struct(pulse_idx).webcam.fs_variation = fs_variation(pulse_idx);
    end
end

if options.SaveStructs
    save(structFile, 'sync_struct', '-append');
end

function [fs, fs_variation] = computeInterPulseFrameRate(pulse_times, onset_cumulative)
% Estimate instantaneous frame rate at each pulse from the cumulative flash
%   onset samples and the pulse times, averaging the rate measured back to the
%   previous pulse and forward to the next pulse. fs_variation is the absolute
%   difference between those two one-sided estimates, and is NaN at the end
%   points where only one estimate is available.
num_pulses = numel(pulse_times);
fs = nan(1, num_pulses);
fs_variation = nan(1, num_pulses);
for pulse_idx = 1:num_pulses
    if pulse_idx > 1
        prev_dt = pulse_times(pulse_idx) - pulse_times(pulse_idx-1);
        prev_fs = (onset_cumulative(pulse_idx) - onset_cumulative(pulse_idx-1)) / prev_dt;
    else
        prev_fs = nan;
    end

    if pulse_idx < num_pulses
        next_dt = pulse_times(pulse_idx+1) - pulse_times(pulse_idx);
        next_fs = (onset_cumulative(pulse_idx+1) - onset_cumulative(pulse_idx)) / next_dt;
    else
        next_fs = nan;
    end

    if isnan(prev_fs) && isnan(next_fs)
        error('Could not calculate any frame rate for pulse #%d', pulse_idx);
    elseif isnan(prev_fs)
        fs(pulse_idx) = next_fs;
    elseif isnan(next_fs)
        fs(pulse_idx) = prev_fs;
    else
        fs(pulse_idx) = mean([prev_fs, next_fs]);
        fs_variation(pulse_idx) = abs(prev_fs - next_fs);
    end
end
