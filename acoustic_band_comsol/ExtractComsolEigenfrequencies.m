function f = ExtractComsolEigenfrequencies(model, n)
%EXTRACTCOMSOLEIGENFREQUENCIES Read eigenfrequencies from the latest study.

if nargin < 2
    n = inf;
end

vars = {'freq', 'acpr.freq'};
f = [];
for i = 1:numel(vars)
    attempts = {@() mphglobal(model, vars{i}, 'dataset', 'dset1', 'solnum', 'all'), ...
                @() mphglobal(model, vars{i})};
    for j = 1:numel(attempts)
        try
            val = attempts{j}();
            val = real(val(:));
            val = val(isfinite(val) & val >= 0);
            if ~isempty(val)
                f = sort(val);
                break;
            end
        catch
        end
    end
    if ~isempty(f)
        break;
    end
end

if isempty(f)
    attempts = {@() mphglobal(model, 'lambda', 'dataset', 'dset1', 'solnum', 'all'), ...
                @() mphglobal(model, 'lambda')};
    for i = 1:numel(attempts)
        try
            ev = attempts{i}();
            ev = ev(:);
            val = real(sqrt(abs(ev))) / (2 * pi);
            val = val(isfinite(val) & val >= 0);
            if ~isempty(val)
                f = sort(val);
                break;
            end
        catch
        end
    end
end

if isempty(f)
    try
        info = mphsolinfo(model);
        if isfield(info, 'solvals') && ~isempty(info.solvals)
            val = real(info.solvals(:));
            val = val(isfinite(val) & val >= 0);
            f = sort(val);
        end
    catch
    end
end

if isempty(f)
    error('ExtractComsolEigenfrequencies:NoFrequencies', ...
        'Could not extract finite eigenfrequencies from COMSOL result.');
end

if isfinite(n) && numel(f) > n
    f = f(1:n);
end

end
