unction [SIGNALS,FEATURES,STATES] = process_WP2(earSignals,STATES)
%process_WP2   Perform WP2 processing
%
%USAGE
%      [SIGNALS,FEATURES,STATES] = process_WP2(binaural,STATES)
%
%INPUT PARAMETERS
%     binaural : binaural signal [nSamples x 2]
%       STATES : settings
% 
%OUTPUT PARAMETERS
%      SIGNALS : extracted signals (e.g. output of gammatone filterbank)
%     FEATURES : extracted features (e.g. estimated ITD / azimuth)
%       STATES : settings

%   Developed with Matlab 8.2.0.701 (R2013b). Please send bug reports to:
%   
%   Author  :  Tobias May, Nicolas Le Goff � 2013, 2014
%              Technical University of Denmark
%              tobmay@elektro.dtu.dk
%              nlg@elektro.dtu.dk
% 
%   History :  
%   v.0.1   2014/01/31
%   ***********************************************************************

%% CHECK INPUT ARGUMENTS 
% 
% 
% Check for proper input arguments
if nargin ~= 2
    help(mfilename);
    error('Wrong number of input arguments!')
end

% Short cut
fsHz = STATES.signal.fsHz;



%% CREATE PERIPHERAL AUDITORY SIGNAL
% 
% Input: Ear signals [nSamples x 2]
% Output: Peripheral auditory signals [nSamples x nAuditoryChannels x 2]
%
% Compute peripheral auditory signal
SIGNALS.auditorySignals = PeripheralProcessing(earSignals,fsHz,STATES.periphery);


%% PERFORM FRAMING
% 
% Input:  Peripheral auditory signals 
%         [nSamples x nAuditoryChannels x 2]
% 
% Output: Frame-based peripheral auditory signals 
%         [Framesize x nFrames x nAuditoryChannels x 2]
%
% Segment input into overlapping frames



%% CREATE BINAURAL MAP
% 
% Input:  Peripheral auditory signals
% Output: Binaural map
%
% Compute binaural map

% XCORR : [NFrames x nChannels x lags x ild] => ITD & IC
% EC    : [NFrames x nChannels x lags x alpha] => ITD & ILD & IC


SIGNALS.BinauralMap = BinauralProcessing(SIGNALS.auditorySignals,fsHz,STATES.binaural);

%% EXTRACT CUES
%
% Input: Binaural map
% Output: ITD, ILD, IC

% estimateBinauralCues


%% EXTRACT FEATURES
% 
% Do not assume any prior knowledge, extract all potential positions
nSources = inf;
% Estimate sound source azimuth
[azim,salience] = AzimuthExtraction(SIGNALS,STATES,nSources);

%[azim,salience] = estimate_Azimuth(auditorySignals,fsHz,STATES.binaural.winSizeSec,nSources);


% IC-based Cue selecion as an option



%% CREATE OUTPUT 
% 
% 
% Signal struct
SIGNALS.fsHz = STATES.signal.fsHz;
%SIGNALS.periphery.data = auditorySignals;
%SIGNALS.binaural.data  = BinauralMap;

% Feature struct
FEATURES.azimuth.direction = azim;
FEATURES.azimuth.salience  = salience;

% STATES struct
% STATES = STATES;


