function bitstream = afsk_demodulate(audio, fs)

audio = audio(:);
audio = audio / (max(abs(audio)) + 1e-6);

Rb = 1200;
Ns = round(fs / Rb);

f_mark  = 1200;
f_space = 2200;

% Goertzel setup
k_mark  = round(f_mark * Ns / fs);
k_space = round(f_space * Ns / fs);

w_mark  = 2*pi*k_mark/Ns;
w_space = 2*pi*k_space/Ns;

coeff_mark  = 2*cos(w_mark);
coeff_space = 2*cos(w_space);

best_bits = [];
best_score = -inf;

for offset = 1:Ns
    
    idx = offset;
    bits = [];
    
    while (idx + Ns - 1) <= length(audio)
        
        segment = audio(idx : idx + Ns - 1);
        
        % --- MARK ---
        s_prev = 0; s_prev2 = 0;
        for n = 1:Ns
            s = segment(n) + coeff_mark*s_prev - s_prev2;
            s_prev2 = s_prev;
            s_prev = s;
        end
        power_mark = s_prev2^2 + s_prev^2 - coeff_mark*s_prev*s_prev2;
        
        % --- SPACE ---
        s_prev = 0; s_prev2 = 0;
        for n = 1:Ns
            s = segment(n) + coeff_space*s_prev - s_prev2;
            s_prev2 = s_prev;
            s_prev = s;
        end
        power_space = s_prev2^2 + s_prev^2 - coeff_space*s_prev*s_prev2;
        
        bits(end+1) = (power_mark > power_space);
        
        idx = idx + Ns;
    end
    
    % 🔥 BEST SCORING METHOD
    try
        [~,~,~] = ax25_decode(bits);
        score = 100;   % perfect decode
    catch
        score = 0;
    end
    
    if score > best_score
        best_score = score;
        best_bits = bits;
    end
end

% fallback (if no perfect decode found)
if isempty(best_bits)
    best_bits = bits;
end

bitstream = best_bits;

end