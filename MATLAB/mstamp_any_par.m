% STOMP Based mSTAMP with Parallelization (Parallel Computing Toolbox)
% Chin-Chia Michael Yeh
%
% [pro_mul, pro_idx] = mstamp_par(data, sub_len, n_work)
%
% Output:
%     pro_mul: multidimensional matrix profile (matrix)
%     pro_idx: matrix profile index (matrix)
% Input:
%     data: input time series (matrix)
%     sub_len: interested subsequence length (scalar)
%     n_work: number of walker for parfor (scalar)
%
% C.-C. M. Yeh, N. Kavantzas, and E. Keogh, "Matrix Profile VI: Meaningful
% Multidimensional Motif Discovery," IEEE ICDM 2017.
% https://sites.google.com/view/mstamp/
% http://www.cs.ucr.edu/~eamonn/MatrixProfile.html
%

function [pro_mul, pro_idx] = ...
    mstamp_any_par(data, sub_len, pct_stop, n_work)
%% setup pool
if isempty(which('parpool'))
    if matlabpool('size') <= 0 %#ok<*DPOOL>
        matlabpool(n_work);
    elseif matlabpool('size')~= n_work
        matlabpool('close');
        matlabpool(n_work);
    end
else
    pool = gcp('nocreate');
    if isempty(gcp('nocreate'))
        parpool(n_work);
    elseif pool.NumWorkers ~= n_work
        delete(gcp('nocreate'));
        parpool(n_work);
    end
end

%% get various length
exc_zone = round(sub_len / 2);
data_len = size(data, 1);
n_dim = size(data, 2);
pro_len = data_len - sub_len + 1;

%% check input
if sub_len > data_len / 2
    error(['Error: Time series is too short relative to desired ' ...
        'subsequence length']);
end
if sub_len < 4
    error('Error: Subsequence length must be at least 4');
end

%% check skip position
skip_loc = false(pro_len, 1);
for i = 1:pro_len
    if any(isnan(reshape(data(i:i+sub_len-1, :), 1, []))) ...
            || any(isinf(reshape(data(i:i+sub_len-1, :), 1, [])))
        skip_loc(i) = true;
    end
end
data(isnan(data)) = 0;
data(isinf(data)) = 0;

%% initialization
data_freq = zeros((sub_len + data_len), n_dim);
data_mu = zeros(pro_len, n_dim);
data_sig = zeros(pro_len, n_dim);
for i = 1:n_dim
    [data_freq(:, i), data_mu(:, i), data_sig(:, i)] = ...
        mass_pre(data(:, i), data_len, sub_len);
end

%% initialize variable
idx = 1:pro_len;
idx(skip_loc) = [];
idx = idx(randperm(length(idx)));
itr_stop = round(length(idx) * pct_stop);
idx = idx(1:itr_stop);
per_work = round(length(idx) / n_work);
idx_work = cell(n_work, 1);
pro_muls = cell(n_work, 1);
pro_idxs = cell(n_work, 1);
for i = 1:n_work
    idx_st = (i - 1) * per_work + 1;
    if i == n_work
        idx_ed = length(idx);
    else
        idx_ed = i * per_work;
    end
    idx_work{i} = idx(idx_st:idx_ed);
    pro_muls{i} = inf(pro_len, n_dim);
    pro_idxs{i} = inf(pro_len, n_dim);
end

%% compute the matrix profile
parfor i = 1:n_work
    dist_pro = zeros(pro_len, n_dim);

    for j = 1:length(idx_work{i})
        idx = idx_work{i}(j);
        fprintf('%d-%d %d\n', i, j, length(idx_work{i}));
        query = data(idx:idx+sub_len-1, :);
        for k = 1:n_dim
            [dist_pro(:, k), ~] = ...
                mass(data_freq(:, k), query(:, k), ...
                data_len, sub_len, data_mu(:, k), ...
                data_sig(:, k), data_mu(idx, k), ...
                data_sig(idx, k));
        end
        dist_pro = real(dist_pro);
        dist_pro = max(dist_pro, 0);

        % apply exclusion zone
        exc_zone_st = max(1, idx - exc_zone);
        exc_zone_ed = min(pro_len, idx + exc_zone);
        dist_pro(exc_zone_st:exc_zone_ed, :) = inf;
        dist_pro(data_sig < eps) = inf;
        if skip_loc(idx)
            dist_pro = inf(size(dist_pro));
        end
        dist_pro(skip_loc, :) = inf;

        % figure out and store the nearest neighbor
        dist_pro_sort = sort(dist_pro, 2);
        dist_pro_cum = zeros(pro_len, 1);
        dist_pro_merg = zeros(pro_len, 1);
        for k = 1:n_dim
            dist_pro_cum = dist_pro_cum + dist_pro_sort(:, k);
            dist_pro_merg(:) = dist_pro_cum / k;
            update_idx = dist_pro_merg < pro_muls{i}(:, k);
            pro_muls{i}(update_idx, k) = dist_pro_merg(update_idx);
            pro_idxs{i}(update_idx, k) = idx;
        end
    end
    pro_muls{i} = sqrt(pro_muls{i});
end

%% merge workers' result
pro_mul = inf(pro_len, n_dim);
pro_idx = inf(pro_len, n_dim);
for i = 1:n_work
    for j = 1:n_dim
        update_idx = pro_muls{i}(:, j) < pro_mul(:, j);
        pro_mul(update_idx, j) = pro_muls{i}(update_idx, j);
        pro_idx(update_idx, j) = pro_idxs{i}(update_idx, j);
    end
end

%% The following two functions are modified from the code provided in the following URL
%  http://www.cs.unm.edu/~mueen/FastestSimilaritySearch.html
function [data_freq, data_mu, data_sig] = mass_pre(data, data_len, sub_len)
data(data_len+1:(sub_len+data_len)) = 0;
data_freq = fft(data);
data_cum = cumsum(data);
data2_cum =  cumsum(data.^2);
data2_sum = data2_cum(sub_len:data_len) - ...
    [0; data2_cum(1:data_len-sub_len)];
data_sum = data_cum(sub_len:data_len) - ...
    [0; data_cum(1:data_len-sub_len)];
data_mu = data_sum./sub_len;
data_sig2 = (data2_sum./sub_len)-(data_mu.^2);
data_sig2 = real(data_sig2);
data_sig2 = max(data_sig2, 0);
data_sig = sqrt(data_sig2);

function [dist_pro, last_prod] = mass(data_freq, query, ...
    data_len, sub_len, data_mu, data_sig, query_mu, query_sig)
% proprocess query for fft
query = query(end:-1:1);
query(sub_len+1:(sub_len+data_len)) = 0;

% compute the product
query_freq = fft(query);
product_freq = data_freq.*query_freq;
product = ifft(product_freq);

% compute the distance profile
dist_pro = 2 * (sub_len - ...
    (product(sub_len:data_len) - sub_len*data_mu*query_mu)./...
    (data_sig * query_sig));
last_prod = real(product(sub_len:data_len));