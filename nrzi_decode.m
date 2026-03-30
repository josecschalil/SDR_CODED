function bits = nrzi_decode(nrzi_bits)
% NRZI Decoding
% Input:
%   nrzi_bits - NRZI encoded binary array (0/1)
%
% Output:
%   bits      - decoded original bits

% Ensure row vector
nrzi_bits = nrzi_bits(:).';

% Preallocate
bits = zeros(size(nrzi_bits));

% Initial previous state = 1 (same as encoder start)
prev = 1;

for i = 1:length(nrzi_bits)
    if nrzi_bits(i) ~= prev
        bits(i) = 0; % transition → 0
    else
        bits(i) = 1; % no transition → 1
    end
    
    % Update previous state
    prev = nrzi_bits(i);
end

end