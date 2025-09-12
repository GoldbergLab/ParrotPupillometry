function onsets = findSyncClickOnsets(audio, threshold, debounce_time)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% findSyncClickOnsets: Find synchronization "clicks" in audio data
% usage: onsets = findSyncClickOnsets(audio)
% usage: onsets = findSyncClickOnsets(audio, threshold, debounce_time)
%
% where,
%    audio is a 1D vector representing an audio signal
%    threshold is a threshold defining the minimum amplitude for a sync 
%       click in arbitrary audio input units
%    debounce_time is the minimum amount of time between sync clicks in
%       units of audio samples
%    onsets is a 1D vector of sync click onsets, in units of audio samples
%
% For post-hoc audio/video synchronization, a simultaneous light/sound 
%   signal is recorded such that light onsets and "click" onsets can be
%   matched up.
% This function takes a vector of audio values, and identifies the start
%   times of any and all recorded synchronization clicks.
%
% See also:
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
arguments
    audio
    threshold numeric = 1.5
    debounce_time numeric = 50000
end
