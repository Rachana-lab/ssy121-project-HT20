close all
clear

%% Input parameters
N = 432;    % Number of bits to transmit
Rb = 440;   % bit rate [bit/sec]
fs = 4400; % Sampling frequency [Sample/s]
Ts = 1/fs; % Sample time [s/Sample]
fc = 1000;  % Carrier frequency [Hz]
span = 6;   % Pulse-width in symbol times.

rolloff = 0.4; % Roll-off factor (ie. alpha) for Raised Cosine pulse.

%% Transmitter
%% Constellation (normalized to unit energy E=d^2)
%constellation = [1 -1]; % BPSK
%constellation = [(1 + 1i), (1 - 1i), (-1 -1i), (-1 + 1i)]/sqrt(2);% Constellation 1 - QPSK/4-QAM
constellation = [sqrt(2), (1 + 1i), sqrt(2)*1i, (-1 + 1i), -sqrt(2), (-1 -1i), -sqrt(2)*1i, (1 - 1i)]/sqrt(2);  % 8-PAM

% % Generate matrix of 16-QAM points.
% order = 16  % Number of QAM constellation points.
% d_min = 2;  % Minimum distance between symbols.
% constx = 0:d_min:(sqrt(order)-1)*d_min
% constx = repmat(constx, sqrt(order),1)
% consty = 0:d_min:(sqrt(order)-1)*d_min
% consty = repmat(consty', 1, sqrt(order))
% const = constx+1i*consty % Make each point into complex number.
% const = const - (3+3i); % Translate matrix to center on origin.
% % Next step: organise constellation matrix elements into vector sorted in
% % gray sequence.
% plot(const, 'ob')
% grid on
% 
% constellation = reshape(const, [1 16])
% plot(const, 'ob')
% grid on

grid on;
if length(constellation)>2 % Voronoi need at least 3 constellation points.
    voronoi(real(constellation), imag(constellation))
end
title('Constellation plot')
xlabel("Phase"); ylabel("Quadrature");


% Preamble (including initial delay where nothing is tx'd)
delay_time = randi([1,20], 1);       % Generate a random delay between 1 and 20 samples long.
delay = zeros(1, delay_time);
preamble = [1 1 1 1 1 -1 -1 1 1 -1 1 -1 1]; % Barker-13
%preamble = [1 1 1 -1 -1 1 -1]; % Barker-7

%preamble_symbs = preamble.*(1+1i)./sqrt(2); % Map preamble to symbols, so that they are 180deg apart! MUST BE MODIFIED IF USING DIFFERENT CONSTELLATION.
preamble_symbs = preamble; % Do NOT need to map to valid symbols

%% Data source
% b = randsrc(1,N,[0 1]); % Random message bits.

string = 'SSY121 Group 7 says: The Capital Of Hawaii Is Honolulu.';
b = string2bitStream(string);
b = [b zeros(1, 432-length(b))]; % Pad string with zeros to fill length 432 packet.
disp(['Sent message: ' string])

%% Bits to Messages
M = length(constellation);      % M unique messages/symbols.
bpsymb = log2(M);       % Bits per symbol
Rsymb = Rb/bpsymb;
Tsymb = 1/Rsymb;
sps   = fs/Rsymb; % Samples per symbol. [Sample/s / Symbol/s = Sample/Symbol] 
m = buffer(b, bpsymb)'; % Group information bits into bits per symbol
m_idx = bi2de(m, 'left-msb')'+1; % Bits to symbol index, msb: the Most Significant Bit

% Message to symbol
message_symbs = constellation(m_idx);    % Map messages to constellation symbols using indices
%symbs = [delay preamble_symbs ]; % Prepend variable delay and preamble to message.
symbs = [delay preamble_symbs message_symbs];


% Generate basic pulse
[pulse t] = rtrcpuls(rolloff, Tsymb, fs, span); % Generate basis pulse.
figure
plot(t, pulse); grid on; title('Basic pulse');

% Pulse-modulation -> create baseband signal
sps = fix(sps); % Convert explicitly to integer !!UGLY HACK!!
x_upsample = upsample(symbs, sps); % Upsample to fs.
s = conv(pulse, x_upsample); % Pulse shaping the symbol-train by convolving with basis pulse.
t_s = (0:length(s)-1).*Ts; % Signal time-axis ie. x[n]*n*Ts.

% Normalize baseband amplitude to sqrt(2) (because pulse-convolution attenuates signal).
s = s.*(sqrt(2)/find_largest_magnitude(real(s)));
scatterplot(s)


figure
subplot(221) 
plot(real(s))
grid on; title('Real pulse-modulated baseband');

subplot(223)
stem(real(x_upsample))
grid on; title('Real symbol baseband');

subplot(222) 
plot(imag(s))
grid on; title('Imag pulse-modulated baseband');

subplot(224)
stem(imag(x_upsample))
grid on; title('Imag symbol baseband');

I = real(s);
Q = imag(s);

tx_sig = I.*cos(2*pi*fc*(t_s)) - Q.*sin(2*pi*fc*(t_s));
figure
plot(t_s, tx_sig); 
title('Carrier signal')
grid on;


%% Channel (AWGN)
SNRdB = 10;
s_noisy = awgn(tx_sig, SNRdB, 'measured');
figure; plot(real(s_noisy))
title('Carrier signal with Noise')

%% Receiver

phzOffs = 2*pi/7;% Phase offset
rx_I =  s_noisy.*cos(2*pi*fc*t_s + phzOffs);
rx_Q = -s_noisy.*sin(2*pi*fc*t_s + phzOffs);

figure
subplot(121)
plot(t_s, rx_I)
title('RX-I, mixed')
subplot(122)
plot(t_s, rx_Q)
title('RX-Q, mixed')

% Lowpass filter to give baseband signal.
rx_I_filtered = lowpass(rx_I, Rsymb, fs, 'ImpulseResponse','iir','Steepness',0.75);
rx_Q_filtered = lowpass(rx_Q, Rsymb, fs, 'ImpulseResponse','iir','Steepness',0.75);

figure
subplot(121)
plot(t_s, rx_I_filtered)
title('RX-I, filtered')
subplot(122)
plot(t_s, rx_Q_filtered)
title('RX-Q, filtered')

% Matched filter
MF = fliplr(conj(pulse));        %create matched filter impulse response
MF_I_output = filter(MF, 1, rx_I_filtered); 
MF_I_output = MF_I_output(length(MF):end); %remove transient
MF_Q_output = filter(MF, 1, rx_Q_filtered); 
MF_Q_output = MF_Q_output(length(MF):end); %remove transient

figure
subplot(121)
plot(MF_I_output)
hold on
grid on; title('RX-I, matched-filtered')
subplot(122)
plot(MF_Q_output)
grid on; title('RX-Q, matched-filtered')

% Synchroniser (TODO)
rx_symbs = [MF_I_output(1:sps:end)', MF_Q_output(1:sps:end)']; % This assumes PERFECT synchronization.

% Plot sample points on baseband signal.
figure
subplot(121)
plot(MF_I_output)
hold on
stem(1:sps:length(MF_I_output), MF_I_output(1:sps:end))
grid on; title('RX-I, sampled')
subplot(122)
plot(MF_Q_output)
hold on
stem(1:sps:length(MF_Q_output), MF_Q_output(1:sps:end))
grid on; title('RX-Q, sampled')
hold off

% Unmapping to symbols
samples = rx_symbs(:,1) + 1i.*rx_symbs(:,2);
figure
hold on
if length(constellation)>2
    voronoi(real(constellation), imag(constellation))
end
plot(samples, 'o')
hold off
axis square; grid on
% xlim([-1 1]);
% ylim([-1 1]);
title('Received samples');

% Preamble correlation
sample_corr = conv(samples, fliplr(preamble));
[~,peak_idx] = max(sample_corr);
figure
subplot(311)
plot(abs(sample_corr))
hold on; plot(peak_idx, abs(sample_corr(peak_idx)), 'or')
grid on
subplot(312)
plot( real(sample_corr) )
grid on
subplot(313)
plot(imag(sample_corr))
grid on

% Attempt to use preamble to find phase errors/ambiguities.
% eg. if there is a phase error of 90deg, there will be a correlation, but
% negative in one of the I/Q streams.
phzError = angle(sample_corr(peak_idx))%-pi/4 % Offset by nominal phase of preamble.
samples_phzCorrected = samples.*exp(1i*-phzError); 

% Normalize signal amplitude using preamble
samples_phzCorrected = samples_phzCorrected./abs(samples(peak_idx));

% Plot phase-corrected samples.
figure
hold on
plot(samples_phzCorrected, 'ob'); title('Phase-corrected rx. Decision regions overlaid.')
if length(constellation)>2
    voronoi(real(constellation), imag(constellation))
end
hold off

% Minimum euclidean distance. Unmap symbols to messages
d = abs(repmat(samples_phzCorrected, 1, length(constellation)) - repmat(constellation, length(samples), 1)).^2; % Compute distance of every sample symbol to every constellation point.
[~, nearest_idx] = min(d, [], 2);  % Get index of value with minimum distance to a constellation point. Traverse along column.

rx_mapped = constellation(nearest_idx); % Choose corresponding symbol.

% Preamble detection
%corr = conv(rx_mapped, fliplr(preamble)); % Compare preamble to received symbol vector. Peak at end of preamble.
%[~,peak_idx] = max(corr);



% Symbols to messages
m_hat = rx_mapped(peak_idx+1:end); % Get symbols after preamble -> actual message.
SER = symerr(message_symbs, m_hat) 

% Messages to bits
b_hat_buffer = de2bi(nearest_idx(peak_idx+1:end)-1, bpsymb, 'left-msb')';
b_hat = b_hat_buffer(:)'; %write as a vector
BER = biterr(b, b_hat) %count of bit errors

b_hat_trunc = b_hat(1:end-rem(length(b_hat), 7)); % Truncate received bitstream so that it's divisible by 7 (ASCII length).
disp(['Received message: ' bitStream2string(b_hat_trunc)])

