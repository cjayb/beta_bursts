function bursts = beta_bursts(eeg,srate,showfigs,opt)
% Paul M Briley 22/10/2020 (pmbriley@outlook.com)
% beta_bursts - version 1.3
%
% bursts = beta_bursts(eeg,srate,showfigs,opt)
%
% Matlab function for identifying beta-frequency bursts/events in single-channel electrophysiological data
% 
% returns timings of beta bursts in sample points and in seconds, as well as spectral power and peak frequency of each burst
% also returns burst duration and spectral width (currently a test feature)
% plots data time course, and time-frequency spectrogram, with beta bursts marked
%
% based on work by Shin et al. (2017), eLife 6: e29086
% (see also their beta burst identification code available at: https://github.com/hs13/BetaEvents)
%
% version 1.0 (24/6/2020) - Paul M Briley (PMB)
% published version
%
% version 1.1 (07/10/2020) - PMB
% change to default value of opt.propPwr to improve identification of burst duration and spectral width
%
% version 1.2 (08/10/2020) - PMB
% added calculation of power at time of beta bursts for frequency bands specified in opt.bands
%
% version 1.3 (22/10/2020) - PMB
% outputs now returned as fields in structure 'bursts'
%
% requires
% Matlab image processing toolbox
% mfeeg toolbox by Xiang Wu et al. - http://sourceforge.net/p/mfeeg - for computing Morlet time-frequency spectrograms
% Find_Peaks.m - https://gist.github.com/tonyfast/d7f6212f86ee004a4d2b - for finding peaks in spectrograms using image dilatation method
% EEGLAB - uses eegplot to display time course
%
% inputs
% eeg: row vector containing time course
% srate: sample rate in Hz
% showfigs: display time course and spectrograms (true/false)
% opt (options): structure with fields containing analysis parameters...
%
% opt.m: number of morlet cycles for time-frequency analysis
% opt.f0s: vector of frequencies for morlet analysis
% opt.nMeds: threshold for identifying beta events = median power for a frequency * opt.nMeds
% opt.propPwr: threshold for determining when a beta burst starts/ends (proportion of peak power) 
% opt.filt2d: standard deviations for 2D gaussian filter applied to time-frequency spectrograms
% opt.peakFreqs: frequency window to identify peaks in time-frequency spectrogram
% opt.structElem: dimensions of structuring element for image dilatation used in peak identification procedure
% opt.eventGap: minimum gap between beta events in seconds
% opt.dispFreqs: frequency range used for plotting spectrograms and beta events (two elements)
% opt.dispBox: if true, encloses starts and ends, and lower and upper limits of spectral widths, of bursts on spectrograms
% opt.markDur: if true, marks starts and ends of bursts on the scrolling plot of eeg activity
% opt.bands: frequency bands for measuring power at the times of beta bursts (rows = bands, columns = edges of bands in Hz)

% outputs
% bursts: structure with fields containing burst properties...
% bursts.tp: locations of beta events in time points
% bursts.secs: locations of beta events in seconds
% bursts.freqs: peak frequency of each beta event in Hz
% bursts.pwr: spectral power of each beta event
% bursts.dur: duration of each beta event in ms
% bursts.spec: spectral width of each beta event in Hz
% bursts.thresh: threshold power values used at each frequency
% bursts.bandsPower: power in frequency bands specified in opt.bands at times of bursts

if nargin<2; error('bursts = beta_bursts(eeg,srate,showfigs,opt)'); end
if nargin<3; showfigs = false; end
if nargin<4; opt = []; end

% prepare optional arguments
args = [];
if ~isfield(opt,'m');                  opt.m = 5;                            else; args = [args 'm ']; end
if ~isfield(opt,'f0s');                opt.f0s = 0.1:0.1:40;                 else; args = [args 'f0s ']; end
if ~isfield(opt,'nMeds');              opt.nMeds = 6;                        else; args = [args 'nMeds ']; end
if ~isfield(opt,'propPwr');            opt.propPwr = 0.5;                    else; args = [args 'propPwr ']; end
if ~isfield(opt,'filt2d');             opt.filt2d = [1 3];                   else; args = [args 'filt2d ']; end
if ~isfield(opt,'peakFreqs');          opt.peakFreqs = [13 30];              else; args = [args 'peakFreqs ']; end
if ~isfield(opt,'structElem');         opt.structElem = [5 5];               else; args = [args 'structElem ']; end
if ~isfield(opt,'eventGap');           opt.eventGap = 0.2;                   else; args = [args 'eventGap ']; end
if ~isfield(opt,'dispFreqs');          opt.dispFreqs = [5 35];               else; args = [args 'dispFreqs ']; end
if ~isfield(opt,'dispBox');            opt.dispBox = false;                  else; args = [args 'dispBox ']; end
if ~isfield(opt,'markDur');            opt.markDur = false;                  else; args = [args 'markDur ']; end
if ~isfield(opt,'bands');              opt.bands = [];                       else; args = [args 'bands ']; end

% check required files and introduce
disp(' '); disp('** beta_bursts v1.3 (PMB) **'); disp('(see code for credits)'); disp(' ');
if isempty(args); disp('all arguments set to defaults')
else; fprintf(1,'args accepted: %s\n',args);
end
if ~exist('mf_tfcm.m','file'); error('requires mfeeg toolbox'); end
if ~exist('Find_Peaks.m','file'); error('requires Find_Peaks.m by Tony Fast'); end
if ~exist('imgaussfilt.m','file'); error('requires Matlab image processing toolbox'); end
if showfigs && ~exist('eegplot.m','file')
    if ~exist('eeglab.m','file'); error('requires EEGLAB to display figures');
    else
        disp(' '); disp('figures requested but function eegplot not found, loading EEGLAB'); disp(' ');
        eeglab; disp(' ');
    end
end

fprintf(1,'threshold: %.0f medians\nburst frequency range: %.0f to %.0f Hz\n\n',opt.nMeds,opt.peakFreqs(1),opt.peakFreqs(2));

% compute time-frequency spectrograms using mfeeg toolbox
disp('computing time-frequency spectrogram');
tfr = mf_tfcm(eeg,opt.m,opt.f0s,srate,0,0,'power');

% apply 2D gaussian filter
disp('applying 2D gaussian filter');
tfr = imgaussfilt(tfr,opt.filt2d);
meds = median(tfr(:,srate:end),2); % calculate median across time points (ignoring first second) for each frequency

% find peaks in filtered time-frequency spectogram
disp('finding peaks in filtered time-frequency spectogram');
fInds = find((opt.f0s>=opt.peakFreqs(1)) & (opt.f0s<=opt.peakFreqs(2))); % indices of frequencies for identifying time-frequency peaks
peaks = Find_Peaks(tfr,'neighborhood',opt.structElem); % uses image dilatation procedure as implemented by Tony Fast
[pksX,pksY] = ind2sub(size(tfr),find(peaks)); % pksX is frequency, pksY is time

% accept peaks that exceed threshold
disp('accepting peaks exceeding threshold');
thresh = meds .* opt.nMeds;
accept = [];
for i = 1:length(pksY)
    if tfr(pksX(i),pksY(i)) >= thresh(pksX(i)) % if time-frequency power above threshold...
        if (pksX(i)>=fInds(1)) && (pksX(i)<=fInds(end)) % if frequency in range of interest...
            accept = [accept i];
        end
    end
end
pksX = pksX(accept);
pksY = pksY(accept);

% reject peaks that are too close together
disp('rejecting peaks that are too close together');
keep = true(1,length(pksY));
for i = 1:length(pksY)
    this = pksY(i);
    inds = find(abs(pksY-this)<(opt.eventGap*srate)); % events within minimum gap of index event
    if numel(inds)>1
        pwr = tfr(:,pksY(inds));
        pwrMx = max(pwr,[],1); % maximum power at each event
        [~,toKeep] = max(pwrMx); % keep event with maximum power
        indsBool = false(1,length(inds));
        indsBool(toKeep) = true;
        keep(inds(~indsBool)) = false; % exclude the lower power events within the minimum gap
    end
end
keep(pksY<srate) = false; % exclude events in the first second of the time course
pksX = pksX(keep);
pksY = pksY(keep);

% create outputs
tp = pksY;
secs = tp * (1/srate);
freqs = opt.f0s(pksX)';

% find beta event durations
disp('finding event durations');
pwr = nan(length(pksX),1);
st = pwr; ed = pwr; 
stF = pwr; edF = pwr; % initialised for spectral width step
for i = 1:length(pwr)
    pwr(i) = tfr(pksX(i),pksY(i)); 
    prop = pwr(i) * opt.propPwr; % power threshold to determine start/end of burst
    prev = find(tfr(pksX(i),(pksY(i)-1):-1:1) < prop); % time points below threshold before peak
    post = find(tfr(pksX(i),(pksY(i)+1):end) < prop);  % time points below threshold after peak
    if ~isempty(prev); st(i) = pksY(i) - prev(1); end  % burst start sample point
    if ~isempty(post); ed(i) = pksY(i) + post(1); end  % burst end sample point
end
st = st / srate; % convert to seconds
ed = ed / srate;
dur = 1000 * (ed - st); % burst duration in ms

% find beta event spectral widths
disp('finding spectral widths');
for i = 1:length(pwr)
    prop = pwr(i) * opt.propPwr; % power threshold to determine lower and upper frequency limits of burst
    prev = find(tfr((pksX(i)-1):-1:1,pksY(i)) < prop); % time points below threshold before peak
    post = find(tfr((pksX(i)+1):end,pksY(i)) < prop);  % time points below threshold after peak
    if ~isempty(prev); stF(i) = pksX(i) - prev(1); end % burst lower frequency limit
    if ~isempty(post); edF(i) = pksX(i) + post(1); end % burst upper frequency limit
end
xstF = nan(size(stF)); xedF = nan(size(edF));
xstF(~isnan(stF)) = opt.f0s(stF(~isnan(stF))); % convert to Hz
xedF(~isnan(edF)) = opt.f0s(edF(~isnan(edF)));
stF = xstF; edF = xedF;
spec = edF - stF; % burst spectral width in Hz

% find power in opt.bands at times of beta bursts
if isempty(opt.bands)
    bandsPower = [];
else
    disp('finding power in requested frequency bands');
    nBands = size(opt.bands,1); % number of frequency bands
    nBursts = length(tp); % number of bursts
    bandsPower = nan(nBands,nBursts);
    for i = 1:nBands
        fInds = (opt.f0s>=opt.bands(i,1)) & (opt.f0s<=opt.bands(i,2)); % indices of frequencies for selected band
        for ii = 1:nBursts
            bandsPower(i,ii) = mean(tfr(fInds,pksY(ii))); % calculated from the already-derived time-frequency spectrogram
        end
    end
end

if showfigs
    % create marker structure then display time course with eegplot (from eeglab toolbox)
    ind = 0;
    for i = 1:length(tp)
        ind = ind + 1; events(ind).type = 'beta'; events(ind).latency = tp(i);
        if opt.markDur; ind = ind + 1; events(ind).type = 'beta start'; events(ind).latency = st(i) * srate; end
        if opt.markDur; ind = ind + 1; events(ind).type = 'beta end';   events(ind).latency = ed(i) * srate; end        
    end
    eegplot(eeg,'srate',srate','events',events,'color','on');

    % display spectrogram for selected time windows
    done = false;
    while ~done
        disp(' '); disp('use the controls to scroll through the EEG time course, beta bursts are marked with vertical red lines'); disp(' ');
        disp('enter time window for spectrogram display in seconds (e.g., [2 3]), leave blank to exit): ');
        tWin = input('');
        if isempty(tWin)
            done = true;
        else
            if numel(tWin)==1; tWin(2) = tWin(1) + 1; end % default time window is one-second long
            tInds = srate*[tWin(1) tWin(2)];
            fInds = [find(opt.f0s==opt.dispFreqs(1)) find(opt.f0s==opt.dispFreqs(2))];

            figure;
            imagesc(tWin,opt.dispFreqs,tfr(fInds(1):fInds(2),tInds(1):tInds(2)));
            hold on;
            set(gca,'YDir','normal');
            set(gca,'FontSize',14);
            xlabel('Time (ms)','FontSize',16);
            ylabel('Frequency (Hz)','FontSize',16);
            plot(secs,freqs,'k+','MarkerSize',10,'linewidth',2);
            if opt.dispBox % display a rectangle to mark the start and end, and lower and upper frequency limits, of each burst
                for i = 1:length(secs)
                    if ~isnan(st(i)) && ~isnan(ed(i)) && ~isnan(stF(i)) && ~isnan(edF(i))
                        rectangle('position',[st(i) stF(i) ed(i)-st(i) edF(i)-stF(i)],'edgecolor','r','linewidth',2);
                    end
                end
            end
        end
    end 
end

bursts.tp = tp; % times of bursts in time points
bursts.secs = secs; % times of bursts in seconds
bursts.freqs = freqs; % peak frequency of each burst in Hz
bursts.pwr = pwr; % spectral power of each burst
bursts.dur = dur; % duration of bursts in milliseconds
bursts.spec = spec; % spectral width of each burst in Hz
bursts.thresh = thresh; % threshold power values used at each frequency
bursts.bandsPower = bandsPower; % power in frequency bands specified in opt.bands at times of bursts

disp('done!'); disp(' ');
