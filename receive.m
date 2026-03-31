clc;
clear;

fs = 48000;
fs_sdr = 480000;
freq_dev = 3000;

rx = sdrrx('Pluto');
rx.CenterFrequency = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame = 4096;
rx.GainSource = 'Manual';
rx.Gain = 40;

disp('Listening... (only valid packets will be shown)');

buffer = [];

flag = [0 1 1 1 1 1 1 0];

while true

% Receive chunk
data = rx();
data = double(data);

% FM demod
phase = unwrap(angle(data));
fm = diff(phase);
fm = fm * fs_sdr/(2*pi*freq_dev);

% Append
buffer = [buffer; fm];

% Keep buffer limited
if length(buffer) > fs_sdr
    buffer = buffer(end-fs_sdr+1:end);
end

% Downsample
decim = fs_sdr/fs;
audio = downsample(buffer, decim);

% Bit demod
bits = afsk_demodulate(audio, fs);

% 🔥 STEP 1: Check if frame exists
flag_pos = strfind(bits, flag);

if length(flag_pos) < 2
    continue; % No valid frame → ignore silently
end

% 🔥 STEP 2: Try decoding
try
    [src, dest, msg] = ax25_decode(bits);
    
    % 🔥 VALID PACKET FOUND
    fprintf('\n=== VALID PACKET ===\n');
    fprintf('FROM: %s\n', src);
    fprintf('TO  : %s\n', dest);
    fprintf('MSG : %s\n', msg);
    fprintf('====================\n');
    
    buffer = []; % Clear after success
    
catch
    % Invalid frame → ignore silently
end


end
