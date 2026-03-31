function [iq, durationSeconds] = plutoBuildPacketIQ(srcCall, dstCall, message, cfg)
% Convert a text packet into padded complex FM samples for Pluto SDR TX.

    frame = ax25_encode(srcCall, dstCall, message);
    audio = afsk_modulate(frame, cfg.fs);
    audioUp = resample(audio, cfg.fs_sdr, cfg.fs);
    audioUp = audioUp(:);
    audioUp = audioUp / (max(abs(audioUp)) + 1e-6);

    phase = 2 * pi * cfg.freqDev * cumsum(audioUp) / cfg.fs_sdr;
    iq = exp(1j * phase);

    totalSamples = round(cfg.txPadSeconds * cfg.fs_sdr);
    padding = floor((totalSamples - numel(iq)) / 2);
    padding = max(padding, round(0.2 * cfg.fs_sdr));
    padded = [zeros(padding, 1); iq(:); zeros(padding, 1)];

    if numel(padded) > totalSamples
        iq = padded(1:totalSamples);
    else
        iq = [padded; zeros(totalSamples - numel(padded), 1)];
    end

    durationSeconds = numel(iq) / cfg.fs_sdr;
end
