% diagnose.m — run this ONCE while TX is transmitting
clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;

% Build LPF
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

% Setup RX
rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = fs_sdr;
rx.GainSource         = 'Manual';
rx.Gain               = 20;

fprintf('Waiting for signal...\n');

% Keep grabbing frames until we get one with signal
while true
    data  = rx();
    data  = double(data);
    power = mean(abs(data).^2);
    fprintf('Power: %.4f\n', power);
    if power >= 1.0
        fprintf('Signal captured — running diagnosis\n\n');
        break;
    end
end

% FM demod
fm    = angle(data(2:end) .* conj(data(1:end-1)));
fm    = [fm; fm(end)];
fm    = fm * (fs_sdr / (2 * pi * dev));
fm_f  = filter(lpf, fm);
audio = fm_f(1:decim:end);
audio = audio - mean(audio);
audio = audio / (max(abs(audio)) + 1e-6);

% Get received bits
bits_rx  = afsk_demodulate(audio, fs);

% Generate what TX should have sent
frame_tx = ax25_encode('N0CALL', 'APRS', 'HELLO FROM SDR');

% Compare
len    = min(length(bits_rx), length(frame_tx));
errors = sum(bits_rx(1:len) ~= frame_tx(1:len));

fprintf('Bits compared : %d\n', len);
fprintf('Bit errors    : %d\n', errors);
fprintf('BER           : %.4f\n', errors/len);

mismatches = find(bits_rx(1:len) ~= frame_tx(1:len));
if ~isempty(mismatches)
    m = mismatches(1);
    fprintf('First error at bit : %d\n', m);
    fprintf('TX bits around it  : %s\n', num2str(frame_tx(max(1,m-4) : min(len,m+4))));
    fprintf('RX bits around it  : %s\n', num2str(bits_rx( max(1,m-4) : min(len,m+4))));
else
    fprintf('No bit errors found — bitstream matches TX exactly\n');
end

release(rx);