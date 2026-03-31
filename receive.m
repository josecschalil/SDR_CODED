clc; clear;

fs     = 48000;
fs_sdr = 960000;   % MUST match TX
decim  = fs_sdr / fs;   % = 20 exactly
dev    = 5000;          % MUST match TX deviation

%% Low-pass filter — pass AFSK band, kill noise before decimation
% Passband up to 3 kHz (covers 2200 Hz + margin), stopband at 6 kHz
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

%% SDR setup
rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = fs_sdr;   % 1 full second per frame
rx.GainSource         = 'Manual';
rx.Gain               = 20;       % increase to 40 if power stays below 5

fprintf('==============================\n');
fprintf('RECEIVER ACTIVE — 433 MHz\n');
fprintf('Waiting for signal...\n');
fprintf('==============================\n');

while true
    %% 1 — RECEIVE
    data  = rx();
    data  = double(data);
    power = mean(abs(data).^2);
    fprintf('Power: %.4f  ', power);

    if power < 1.0
        fprintf('(no signal — waiting)\n');
        continue;
    end
    fprintf('(signal detected)\n');

    %% 2 — FM DEMODULATE
    % angle(x[n] * conj(x[n-1])) gives instantaneous phase difference
    fm = angle(data(2:end) .* conj(data(1:end-1)));
    fm = [fm; fm(end)];

    % Scale to recover actual audio amplitude
    % Without this, Goertzel energy levels are arbitrary and comparisons fail
    fm = fm * (fs_sdr / (2 * pi * dev));

    %% 3 — LOW-PASS FILTER (must happen BEFORE decimation)
    fm_filtered = filter(lpf, fm);

    %% 4 — DECIMATE
    audio = fm_filtered(1:decim:end);

    %% 5 — NORMALISE
    audio = audio - mean(audio);
    peak  = max(abs(audio));
    if peak < 1e-4
        fprintf('  audio too quiet after demod — skipping\n');
        continue;
    end
    audio = audio / peak;

    %% 6 — DEBUG PLOTS
    figure(1); clf;
    subplot(2,1,1);
    plot(audio(1:min(500,end)));
    title(sprintf('Audio waveform  (power=%.2f)', power));
    xlabel('Sample'); ylabel('Amplitude');

    subplot(2,1,2);
    [pxx, f] = pwelch(audio, 1024, 512, 4096, fs);
    plot(f, 10*log10(pxx));
    xlim([0 4000]); grid on;
    xline(1200, 'r--', '1200 Hz');
    xline(2200, 'r--', '2200 Hz');
    title('Spectrum — mark=1200 Hz, space=2200 Hz');
    xlabel('Hz'); ylabel('dB');
    drawnow;

    %% 7 — AFSK DEMODULATE
    bits = afsk_demodulate(audio, fs);
    if isempty(bits)
        fprintf('  afsk_demodulate returned empty\n');
        continue;
    end
    fprintf('  bits recovered: %d\n', length(bits));

    %% 8 — AX.25 DECODE
    try
        [src, dest, msg] = ax25_decode(bits);
        fprintf('\n==============================\n');
        fprintf('  MESSAGE RECEIVED\n');
        fprintf('  FROM : %s\n', src);
        fprintf('  TO   : %s\n', dest);
        fprintf('  MSG  : %s\n', msg);
        fprintf('==============================\n\n');
    catch e
        fprintf('  decode failed: %s\n', e.message);
    end
end