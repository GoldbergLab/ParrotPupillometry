function onsets = findSyncFlashOnsets(video, ROI, threshold, debounce_time)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% findSyncClickOnsets: Find synchronization "clicks" in audio data
% usage: onsets = findSyncFlashOnsets(audio, ROI)
% usage: onsets = findSyncFlashOnsets(audio, ROI, threshold, debounce_time)
%
% where,
%    video is a 4D vector (h x w x c x n) representing a video signal
%    ROI is a 1x4 vector representing the ROI in which to look for flashes.
%       It should be in the form [x, y, w, h] where x and y are the 
%       coordinates of the upper left corner of the ROI, and w and h are 
%       the dimensions of the ROI. If left as an empty list (default), the
%       entire video will be used
%    threshold is a threshold defining the minimum amplitude for a sync 
%       click in arbitrary audio input units
%    debounce_time is the minimum amount of time between sync clicks in
%       units of audio samples
%    onsets is a 1D vector of sync click onsets, in units of audio samples
%
% For post-hoc audio/video synchronization, a simultaneous light/sound 
%   signal is recorded such that light onsets and "click" onsets can be
%   matched up.
% This function takes an array representing video data, and identifies the 
%   start times of any and all recorded synchronization flashes.
%
% See also:
%
% Version: 1.0
% Author:  Brian Kardon
% Email:   bmk27=cornell*org, brian*kardon=google*com
% Real_email = regexprep(Email,{'=','*'},{'@','.'})
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
arguments
    video
    ROI numeric = []
    threshold numeric = 1.5
    debounce_time numeric = 50000
end