clc; clear;

fs     = 48000;
fs_sdr = 960000;
dev    = 5000;
msg    = 'HELLO FROM SDR';

MY_CALL  = 'N0CALL';
DEST     = 'APRS';
ACK_CALL = 'N0ACK';    % RX will send ACK from this callsign

%% Build TX frame
frame    = ax25_encode(MY_CALL, DEST, msg);
audio    = afsk_modulate(frame, fs);
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);
phase     = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

%% Pad to exactly 2 seconds
total_samples = 2 * fs_sdr;
signal_len    = length(tx_signal);
pad_each      = floor((total_samples - signal_len) / 2);
pad_each      = max(pad_each, round(0.2 * fs_sdr));
carrier       = zeros(pad_each, 1);
tx_padded     = [carrier; tx_signal(:); carrier];
if length(tx_padded) > total_samples
    tx_final = tx_padded(1:total_samples);
else
    tx_final = [tx_padded; zeros(total_samples - length(tx_padded), 1)];
end

%% Setup TX
tx = sdrtx('Pluto');
tx.CenterFrequency    = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain               = -10;

%% Setup RX (to listen for ACK)
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = fs_sdr;
rx.GainSource         = 'Manual';
rx.Gain               = 40;

fprintf('==============================\n');
fprintf('TX: Sending "%s"\n', msg);
fprintf('Waiting for ACK (timeout 60s)\n');
fprintf('==============================\n');

%% Transmit + listen for ACK
transmitRepeat(tx, tx_final);

ack_received = false;
t_start      = tic;
timeout      = 60;

while toc(t_start) < timeout

    % Half-duplex — brief TX pause to listen for ACK
    % (Pluto can't TX and RX simultaneously on same freq)
    pause(0.2);

    % Grab 3 frames and listen
    data1 = rx(); data2 = rx(); data3 = rx();
    data  = double([data1; data2; data3]);
    power = mean(abs(data).^2);

    fprintf('Listening for ACK — power: %.2f  elapsed: %.0fs\n', ...
            power, toc(t_start));

    if power < 1.0, continue; end

    % FM demod
    fm    = angle(data(2:end) .* conj(data(1:end-1)));
    fm    = [fm; fm(end)];
    fm    = fm * (fs_sdr / (2*pi*dev));
    fm_f  = filter(lpf, fm);
    audio_rx = fm_f(1:fs_sdr/fs:end);
    audio_rx = audio_rx - mean(audio_rx);
    audio_rx = audio_rx / (max(abs(audio_rx)) + 1e-6);

    bits = afsk_demodulate(audio_rx, fs);
    if isempty(bits), continue; end

    try
        [src, dest, ack_msg] = ax25_decode(bits);
        fprintf('Received from %s: %s\n', src, ack_msg);

        % Check if it is our ACK
        if strcmp(src, ACK_CALL) && contains(ack_msg, 'ACK')
            ack_received = true;
            fprintf('\n==============================\n');
            fprintf('  ACK RECEIVED FROM %s\n', src);
            fprintf('  MSG : %s\n', ack_msg);
            fprintf('  TIME: %.1f sec\n', toc(t_start));
            fprintf('==============================\n');
            break;
        end
    catch
    end
end

%% Stop TX
release(tx);
release(rx);

if ack_received
    fprintf('\nTX complete — message acknowledged.\n');
else
    fprintf('\nTX timed out after %.0f seconds — no ACK received.\n', timeout);
end