clc;
clear;

%% PARAMETERS
fs = 48000;           % Audio sample rate
fs_sdr = 1000000;     % SDR sample rate
freq_dev = 3000;      % FM deviation

%% SDR SETUP
rx = sdrrx('Pluto');
rx.CenterFrequency = 433e6;   % Adjust slightly if needed
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame = 4096;
rx.GainSource = 'Manual';
rx.Gain = 60;

fprintf('==============================\n');
fprintf('RECEIVER STARTED\n');
fprintf('Waiting for packets...\n');
fprintf('==============================\n');

%% BUFFER
buffer = [];
flag = [0 1 1 1 1 1 1 0];

%% BANDPASS FILTER (AFSK: 1200–2200 Hz)
bp = designfilt('bandpassiir', ...
'FilterOrder', 6, ...
'HalfPowerFrequency1', 800, ...
'HalfPowerFrequency2', 2600, ...
'SampleRate', fs_sdr);

%% MAIN LOOP
while true

%% RECEIVE RF
data = rx();
data = double(data);

%% FM DEMOD (ROBUST)
fm = angle(data(2:end) .* conj(data(1:end-1)));
fm = [fm; fm(end)];

%% FILTER (CRITICAL)
fm = filtfilt(bp, fm);

%% ADD TO BUFFER
buffer = [buffer; fm];

%% KEEP BUFFER LIMITED
if length(buffer) > fs_sdr
    buffer = buffer(end-fs_sdr+1:end);
end

%% PROCESS WHEN ENOUGH DATA
if length(buffer) < fs_sdr/2
    continue;
end

%% DOWNSAMPLE (CLEAN)
audio = decimate(buffer(1:fs_sdr/2), round(fs_sdr/fs));

%% SLIDING WINDOW
buffer = buffer(fs_sdr/4:end);

%% DEBUG (OPTIONAL)
% plot(audio(1:200))
% title('Recovered Audio')
% drawnow

%% AFSK DEMOD
bits = afsk_demodulate(audio, fs);

%% FLAG DETECTION
flag_pos = strfind(bits, flag);

if length(flag_pos) < 2
    continue;
end

%% DECODE AX.25
try
    [src, dest, msg] = ax25_decode(bits);

    fprintf('\n📡 RECEIVED PACKET\n');
    fprintf('FROM: %s\n', src);
    fprintf('TO  : %s\n', dest);
    fprintf('MSG : %s\n', msg);
    fprintf('==============================\n');

catch
    % Ignore invalid frames
end


end
