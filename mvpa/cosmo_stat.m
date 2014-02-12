function stat_ds=cosmo_stat(ds, stat_name, output_stat_name)
% compute one-sample t, two-sample t, or F statistic
%
% stat_ds=cosmo_stats(ds, stat_name[, output_stat_name])
%
% Inputs:
%   ds                dataset struct with PxQ .samples and Px1 .sa.targets;
%                     .sa.targets indicate the conditions (levels).
%   stat_name         One of:
%                     't' : one-sample t-test against zero.
%                     't2': two-sample t-test with equal variance,
%                           computing classes(1) minus classes (2), where
%                           classes=unique(ds.sa.targets).
%                     'F' : one-way ANOVA.
%   output_stat_name  (optional) 'z', 'p', 'left', 'right', 'both', or 
%                      empty (default). 
%                     - 'z' returns a z-score.
%                     - 'left', 'right', and 'both' return a p-value with 
%                        the specified tail. 
%                     - 'p' returns a p-value, with tail='right' if
%                        stat_name='F' and tail='both' otherwise.
%
% Returns:
%   stat_ds          dataset struct with fields:
%     .samples       1xQ statistic value, or (if output_stat_name is 
%                    non-empty) z-score or p-value. See the Notes below
%                    for interpreting p-values.
%     .sa.df         if output_stat_name is empty the degrees of freedom
%                    as scalar (if stat_name is 't' or 't2') or 1x2 vector
%                    (if stat_name is 'F')
%     .sa.labels     set to {stat_name}
%     .[f]a          identical to ds.[f]a, if present.
%
% Notes:
%  - If output_stat_name is not provided or empty, then this function runs 
%    considerably faster than the builtin matlab functions. 
%  - When output_stat_name=='p' then the p-values returned are the same as
%    the builtin matlab functions anova1, ttest, and ttest2 with the 
%    default tails.
%  - For paired-sample t-tests: provide the observation differences
%    to this function.
%  - For one-sample t-tests against x, if x~=0: subtract x from ds.samples.
%
% Examples:
%  - % compute one-way ANOVA F-values
%    >> ds=struct();
%    >> ds.samples=randn(12,100);
%    >> ds.sa.targets=repmat(1:3,1,4)';
%    >> s=cosmo_stat(ds,'F'); % compute F-values
%
%  - % compute two-sample t-test p-values and z-scores
%    >> ds=struct();
%    >> ds.samples=[1+randn(12,100); randn(12,100)]; % } group 1 > group 2
%    >> ds.sa.targets=[ones(12,1); 2*ones(12,1)];    % }
%    >> s=cosmo_stat(ds,'t2','p') % two-sample t-test, return p-palues
%    >> fprintf('ps: %.3f +/- %.3f\n', mean(s.samples), std(s.samples))
%    ps: 0.078 +/- 0.141
%    >> s=cosmo_stat(ds,'F','z') % one-way ANOVA, return z-scores
%    >> fprintf('zs: %.3f +/- %.3f\n', mean(s.samples), std(s.samples))
%    zs: 1.959 +/- 0.932
%
% See also: anova1, ttest, ttest2
%
% NNO Jan 2014

    if nargin<3
        output_stat_name=''; 
    elseif any(cosmo_match({'left','right','both'},output_stat_name))
        tail=output_stat_name;
        output_stat_name='p';
    elseif strcmp(output_stat_name,'p')
        switch stat_name
            case 'F'
                tail='right'; % show anova1  behaviour w.r.t. p-values
            otherwise
                tail='both'; % show ttest[2] "                       "
        end
    end

    samples=ds.samples;
    nsamples=size(samples,1);
    
    % get targets
    if isfield(ds,'sa') && isfield(ds.sa,'targets')
        targets=ds.sa.targets;
    elseif strcmp(stat_name,'t')
        % one-sample t test is allowed to have missing targets
        targets=ones(nsamples,1);
    else
        % all other stats do require targets
        error('Missing field .sa.targets');
    end

    % ensure that targets has the proper size
    if numel(targets)~=nsamples
        error('Targets has %d values, expected %d', ...
                            numel(targets), nsamples);
    end

    % get class information
    classes=unique(targets);
    nclasses=numel(classes);
    
    % Set label to be used for cdf (in case 'p' or 'z' has to be computed).
    % This is only different from stat_name in the case of 't2'
    cdf_label=stat_name;

    % run specified helper function
    switch stat_name
        case 't'
            if nclasses~=1
                error('%s stat: expected 1 class, found %d',...
                            stat_name, nclasses);
            end
            [stat,df]=quick_ttest(samples);

        case 't2'
            if nclasses~=2
                error('%s stat: expected 2 classes, found %d',...
                            stat_name, nclasses);
            end
            [stat,df]=quick_ttest2(samples(targets==classes(1),:),...
                                  samples(targets==classes(2),:));
            cdf_label='t';

        case 'F'
            if nclasses<2
                error('%s stat: expected >=2 classes, found %d',...
                            stat_name, nclasses);
            end 
            if isfield(ds.sa,'contrast')
                contrast=ds.sa.contrast;
            else
                contrast=[];
            end
            
            [stat,df]=quick_ftest(samples, targets, classes, nclasses, ...
                                                            contrast);

        otherwise
            error('illegal statname %s', stat_name);
    end

    % transform output is required
    if isempty(output_stat_name)
        output_stat_name=stat_name;
    else
        % transform to left-tailed p-value
        df_cell=num2cell(df);
        stat=cdf(cdf_label,stat,df_cell{:});
        
        % reset degrees of freedom
        df=[];
        
        switch output_stat_name
            case 'z'
                % transform to z-score
                stat=icdf('norm',stat);
            case 'p'
                switch tail
                    case 'left'
                        % do nothing
                    case 'right'
                        % invert p-value
                        stat=1-stat;
                    case 'both'
                        % take whichever tail is more extreme
                        stat=(.5-abs(stat-.5))*2;
                    otherwise
                        assert(false,'this should not happen');
                end     
            otherwise
                error('illegal output type %s', output_stat_name);
        end
    end

    % store output
    stat_ds=struct();
    if isfield(ds,'a'), stat_ds.a=ds.a; end
    if isfield(ds,'fa'), stat_ds.fa=ds.fa; end
    stat_ds.samples=stat;
    stat_ds.sa.labels={output_stat_name};
    if ~isempty(df)
        stat_ds.sa.df=df;
    end

    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% helper functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [f,df]=quick_ftest(samples, targets, classes, nclasses, contrast)
    % one-way ANOVA
    has_contrast=~isempty(contrast);
    contrast_sum=0;
    
    [ns,nf]=size(samples);
    mu=sum(samples,1)/ns; % grand mean

    b=zeros(nclasses,nf); % between-class sum of squares
    nsc=zeros(nclasses,1);
    wss=0; % within-class sum of squares

    for k=1:nclasses
        msk=classes(k)==targets;

        nsc(k)=sum(msk); % number of samples in this class
        sample=samples(msk,:);
        muc=sum(sample,1)/nsc(k); % class mean

        % between- and within-class sum of squares
        if has_contrast
            cmsk=contrast(msk);
            if ~all(cmsk(1)==cmsk)
                error('Contrast has differerent values in level %d',k);
            end
            contrast_sum=contrast_sum+cmsk(1);
            b(k,:)=sum(bsxfun(@times,contrast(msk),mu-muc),1);
        else
            b(k,:)=(mu-muc);
        end
        wss=wss+sum(bsxfun(@minus,muc,sample).^2,1);
    end

    if has_contrast
        if contrast_sum~=0
            error('contrast has sum %d, should be 0', contrast_sum);
        end
        bss=sum(b,1).^2/sum(contrast.^2);
        df1=1;
    else
        bss=sum(bsxfun(@times,nsc,b.^2),1);
        df1=nclasses-1;
    end
    
    df=[df1,ns-nclasses];

    bss=bss/df(1);
    wss=wss/df(2);

    f=bss./wss;


function [t,df]=quick_ttest(x)
    % one-sample t-test against zero
    
    n=size(x,1);
    mu=sum(x,1)/n; % grand mean

    df=n-1;
    scaling=n*df;

    % sum of squares
    ss=sum(bsxfun(@minus,x,mu).^2,1);
    
    t=mu .* sqrt(scaling./ss);


function [t,df]=quick_ttest2(x,y)
    % two-sample t-test with equal variance assumption
    
    nx=size(x,1);
    ny=size(y,1);
    mux=sum(x,1)/nx; % mean of class x
    muy=sum(y,1)/ny; % "           " y

    df=nx+ny-2;
    scaling=(nx*ny)*df/(nx+ny);
    
    % sum of squares
    ss=sum([bsxfun(@minus,x,mux);bsxfun(@minus,y,muy)].^2,1);

    t=(mux-muy) .* sqrt(scaling./ss);

