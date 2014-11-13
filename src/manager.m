classdef manager < handle
    
    properties
        Processors      % Array of processor objects
        InputList       % Array of input "adresses" to each processors
        OutputList      % Array of output "adresses" to each processors
        Map             % Vector mapping the processing order to the 
                        % processors order. Allows for avoiding to reorder
                        % the processors array when new processors are
                        % added.
        Data            % Pointer to the data object
        
    end
    
    properties (GetAccess = protected)
        use_mex         % Flag for using mex files to speed up computation 
                        % when available
    end
    
    methods
        function mObj = manager(data,request,p,use_mex)
            %manager        Constructs a manager object
            %
            %USAGE
            %       mObj = manager(data,request)
            %       mObj = manager(data,request,p)
            %
            %INPUT ARGUMENTS
            %     data : Handle of an existing data structure
            %  request : Single request as a string (e.g., 'ild'), OR
            %            cell array of requested signals, cues or features
            %            (e.g., request = {'ild','itd'})
            %        p : Single parameter structure, if all requests share
            %            the same parameters, OR cell array of individual
            %            parameter structures corresponding to the request.
            %
            %OUTPUT ARGUMENTS
            %     mObj : Manager instance
            %
            %SEE ALSO: dataObject.m requestList.m genParStruct.m
            
            if nargin>0     % Failproof for Matlab empty calls
            
            % Input check
            if nargin<4||isempty(use_mex);use_mex=1;end
            if nargin<3||isempty(p);p=[];end
            if nargin<2
                request = [];
            end
            if nargin<1
                error(['Too few arguments, the manager is built upon '...
                    'an existing data Object'])
            end
            
            % Add use_mex property for the manager
            mObj.use_mex = use_mex;
            
            % Add pointer to the data structure
            mObj.Data = data;
            
            % Instantiate the requested processors
            if ~isempty(request)
                if iscell(request) && numel(request) == 1
                    % Then we have a one request with multiple parameters
                    if iscell(p)
                        %... with individual parameters
                        for ii = 1:size(p,2)
                            mObj.addProcessor(request,p{ii});
                        end
                    else
                        mObj.addProcessor(request,p);
                    end
                elseif iscell(request)
                    % Then we have a multiple request...
                    if iscell(p)
                        %... with individual parameters
                        if size(request,2)~=size(p,2)
                            error('Number of requests and number of provided parameters do not match')
                        else
                            for ii = 1:size(request,2)
                                mObj.addProcessor(request{ii},p{ii});
                            end
                        end
                    else
                        %... all with the same set of parameters
                        for ii = 1:size(request,2)
                            mObj.addProcessor(request{ii},p);
                        end
                    end
                elseif iscell(p)
                    % Then it is a same request but with multiple parameters
                    for ii = 1:size(p,2)
                        mObj.addProcessor(request,p{ii});
                    end
                else
                    % Then it is a single request
                     mObj.addProcessor(request,p);
                end
            end
            end
        end
        
        function processSignal(mObj)
            %processSignal      Requests a manager object to extract its
            %                   required features for a full signal present
            %                   in mObj.Data.signal
            %
            %USAGE
            %    mObj.processSignal()
            %
            %INPUT ARGUMENT
            %   mObj : Manager object
            %
            %NB: As opposed to the method processChunk, this method will
            %reset the internal states of the processors prior to
            %processing, assuming a completely new signal.
            %
            %SEE ALSO: processChunk
            
            % Check that there is an available signal
            if isempty(mObj.Data.signal)
                warning('No signal available for processing')
            else            
                % Reset the processors internal states
                mObj.reset;
                
                % Number of processors
                n_proc = size(mObj.Processors,1);

                % Loop on each processor
                for ii = 1:n_proc
                    % Get index of current processor
                    jj = mObj.Map(ii);

                    if ~mObj.Processors{jj,1}.isBinaural
                        % Apply processing for left channel (or mono if
                        % interaural cue/feature)
                        mObj.OutputList{jj,1}.setData( ...
                            mObj.Processors{jj,1}.processChunk(mObj.InputList{jj,1}.Data(:)) );

                        % Apply for right channel if stereo cue/feature
                        if mObj.Data.isStereo && ~isempty(mObj.Processors{jj,2})
                            mObj.OutputList{jj,2}.setData(...
                                mObj.Processors{jj,2}.processChunk(mObj.InputList{jj,2}.Data(:))...
                                );
                        end
                    else
                        if ~mObj.Processors{jj,1}.hasTwoOutputs
                            % If the processor extracts a binaural cue, inputs
                            % from left and right channel should be routed
                            mObj.OutputList{jj,1}.setData( ...
                                mObj.Processors{jj,1}.processChunk(mObj.InputList{jj,1}.Data(:),...
                                mObj.InputList{jj,2}.Data(:))...
                                );
                        else
                            if size(mObj.InputList,2)>1
                                [out_l, out_r] = mObj.Processors{jj,1}.processChunk(mObj.InputList{jj,1}.Data(:),...
                                    mObj.InputList{jj,2}.Data(:));
                            else
                                [out_l, out_r] = mObj.Processors{jj,1}.processChunk(mObj.InputList{jj,1}.Data(:),...
                                    []);
                            end
                            mObj.OutputList{jj,1}.setData(out_l);
                            if ~isempty(out_r)
                                mObj.OutputList{jj,2}.setData(out_r);
                            end
                        end
                    end
                end
            end
        end
        
        function processChunk(mObj,sig_chunk,do_append)
            %processChunk   Update the signal with a new chunk of data and
            %               calls the processing chain for this new chunk
            %
            %USAGE
            %   mObj.processChunk(sig_chunk)
            %   mObj.processChunk(sig_chunk,append)
            %
            %INPUT ARGUMENTS
            %      mObj : Manager object
            % sig_chunk : New signal chunk
            %    append : Flag indicating if the newly generated output
            %             should be appended (append = 1) to previous
            %             output or should overwrite it (append = 0,
            %             default)
            %
            %NB: Even if the previous output is overwritten, the
            %processChunk method allows for real-time processing by keeping
            %track of the processors' internal states between chunks.
            %
            %SEE ALSO: processSignal
            
            if nargin<3||isempty(do_append);do_append = 0;end
            
            % Check that the signal chunk has correct number of channels
            if size(sig_chunk,2) ~= mObj.Data.isStereo+1
                % TO DO: Change that to a warning and handle appropriately
                error(['The dimensionality of the provided signal chunk'...
                    'is incompatible with previous chunks'])
            end
            
            % Delete previous output if necessary
            if ~do_append
                mObj.Data.clearData;
            end
            
            
            % Append the signal chunk
            if mObj.Data.isStereo
               mObj.Data.signal{1}.appendChunk(sig_chunk(:,1));
               mObj.Data.signal{2}.appendChunk(sig_chunk(:,2));
            else            
               mObj.Data.signal{1}.appendChunk(sig_chunk);
            end
            
            % Number of processors
            n_proc = size(mObj.Processors,1);
            
            % Loop on each processor
            for ii = 1:n_proc
                % Get index of current processor
                jj = mObj.Map(ii);
                
                if ~mObj.Processors{jj,1}.isBinaural
                    % Apply processing for left channel (or mono if
                    % interaural cue/feature):

                    % Getting input signal handle (for code readability)
                    in = mObj.InputList{jj,1};

                    % Perform the processing
                    out = mObj.Processors{jj,1}.processChunk(in.Data('new'));

                    % Store the result
                    mObj.OutputList{jj,1}.appendChunk(out);

                    % Apply similarly for right channel if binaural cue/feature
                    if mObj.Data.isStereo && ~isempty(mObj.Processors{jj,2})
                        in = mObj.InputList{jj,2};
                        out = mObj.Processors{jj,2}.processChunk(in.Data('new'));
                        mObj.OutputList{jj,2}.appendChunk(out);
                    end
                    
                else
                    % Inputs from left AND right channels are needed at
                    % once
                    
                    % Getting input signal handles for both channels
                    in_l = mObj.InputList{jj,1};
                    
                    if ~mObj.Processors{jj,1}.hasTwoOutputs
                        
                        in_r = mObj.InputList{jj,2};
                        
                        % Perform the processing
                        out = mObj.Processors{jj,1}.processChunk(...
                            in_l.Data('new'),...
                            in_r.Data('new'));

                        % Store the result
                        mObj.OutputList{jj,1}.appendChunk(out);
                    else
                        
                        if size(mObj.InputList,2)>1
                            in_r = mObj.InputList{jj,2};
                            
                            % Perform the processing
                            [out_l, out_r] = mObj.Processors{jj,1}.processChunk(...
                                in_l.Data('new'),...
                                in_r.Data('new'));
                        else
                            % Perform the processing
                            [out_l, out_r] = mObj.Processors{jj,1}.processChunk(...
                                in_l.Data('new'));
                        end

                        % Store the result
                        mObj.OutputList{jj,1}.appendChunk(out_l);
                        
                        if ~isempty(out_r)
                            mObj.OutputList{jj,2}.appendChunk(out_r);
                        end
                    end
                end
                
%                 % Getting input signal handle (for code readability)
%                 in = mObj.InputList{jj};
%                 
%                 % Perform the processing
%                 out = mObj.Processors{jj}.processChunk(in.Data('new'));
%                 
%                 % Store the result
%                 mObj.OutputList{jj}.appendChunk(out);
                
            end
        end
        
        function hProc = hasProcessor(mObj,name,p,channel)
            %hasProcessor       Determines if a processor (including its
            %                   dependencies) already exists
            %
            %USAGE
            %   hProc = mObj.hasProcessor(name,p)
            %   hProc = mObj.hasProcessor(name,p,channel)
            %
            %INPUT ARGUMENTS
            %    mObj : Instance of manager object
            %    name : Name of processor
            %       p : Complete structure of parameters for that processor
            % channel : Channel the sought processor should be acting on
            %           ('left', 'right', or 'mono'). If unspecified, any
            %           processor with matching parameter will be returned.
            %
            %OUTPUT ARGUMENT
            %   hProc : Handle to an existing processor, if any, 0 else
            
            
            ch_name = {'left','right','mono'};
            
            if nargin<4 %|| isempty(channel)
                channel = ch_name;
            elseif ~ismember(channel,ch_name)
                error('Invalid tag for channel name. Valid tags are as follow: %s',strjoin(ch_name))
            end
            
            if ~iscell(channel)
                channel = {channel};
            end
            
            % Initialize the output
            hProc = 0;
            
            % Look into corresponding ear depending on channel request.
            % Left and mono are always in the first column of the
            % processors cell array, right in the second.
            if strcmp(channel,'right')
                earIndex = 2;
            else
                earIndex = 1;
            end
            
            % Loop over the processors to find the ones with suitable name
            for ii = 1:size(mObj.Processors,1)
                
                % Get a handle to that processor, for readability in the
                % following
                proc = mObj.Processors{ii,earIndex};
                
                % Is the current processor one of the sought type?
                if isa(proc,name) && ismember(proc.Output.Channel,channel)
                    
                    % Does it have the requested parameters?
                    if proc.hasParameters(p)
                        
                        % Then it is a suitable candidate, we should
                        % investigate its dependencies
                        while true
                            
                            if isempty(proc.Dependencies{1})
                                % Then we reached the end of the dependency
                                % list without finding a mismatch in
                                % parameters. The original processor is a
                                % solution:
                                hProc = mObj.Processors{ii,earIndex};
                                return
                            end
                            
                            % Set current processor to proc dependency
                            proc = proc.Dependencies{1};
                            
                            % Does the dependency also have requested
                            % parameters? If not, break of the while loop
                            if ~proc.hasParameters(p)
                                break
                            end
                            
                        end
                        
                        
                    end
                    
                end
                
                % If not, move along in the loop
                
            end
            
        end
        
        function [out,varargout] = addProcessor(mObj,request,p)
            %addProcessor       Add new processor needed to compute a
            %                   single request. Optionally returns a handle
            %                   for the requested signal for convenience.
            %
            %USAGE:
            %     mObj.addProcessor(request,p)
            %     out = mObj.addProcessor(...)
            %
            %INPUT ARGUMENTS
            %    mObj : Manager instance
            % request : Requested signal (string)
            %       p : Structure of non-default parameters
            %
            %OUTPUT ARGUMENTS
            %     out : Handle for the requested signal
            %
            % TODO:
            %   - Add support for multiple requests
            %   - Current bug in .cfHz property of signals. This cannot be
            %   taken from p.cfHz but needs to be fetch from dependent
            %   processors. Only affects labeling of the channels.
            
            if nargin<3 || isempty(p)
                % Initialize parameter structure
                p = struct;
            end
            
            % Deal with multiple requests via pseudo-recursion
            if iscell(request) || iscell(p)
                
                if iscell(request) && ~iscell(p)
                    % All the requests have the same parameters, replicate
                    % them
                    p = repmat({p},size(request));
                elseif ~iscell(request) && iscell(p)
                    % One request with different parameters, replicate the request
                    request = repmat({request},size(p));
                end
                
                if size(p,2)~=size(request,2)
                    error(['Provided number of parameter structures'...
                        ' does not match the number of requests made'])
                end
                
                % Call addProcessor method for each individual request
                varargout = cell(1,size(request,2)-1);
                out = mObj.addProcessor(request{1},p{1});
                for ii = 2:size(request,2)
                    varargout{ii-1} = mObj.addProcessor(request{ii},p{ii});
                end
                return
                
            end
            
            if ~isfield(p,'fs')
                % Add sampling frequency to the parameter structure
                p.fs = mObj.Data.signal{1}.FsHz;
            end
            
            % Find out about the Gammatone definition
            if isfield(p,'gt_cfHz')
                % Generated from provided center frequencies
                gamma_init = 'cfHz';
            elseif isfield(p,'gt_nChannels')
                % Generate from upper/lower frequencies and number of
                % channels
                gamma_init = 'nChannels';
            else
                % Generate from upper/lower freqs. and distance between
                % channels
                gamma_init ='standard';
            end
            
            % Add default values for parameters not explicitly defined in p
            p = parseParameters(p,request);
            
            % Try/Catch to check that the request is valid
            try 
                % TO DO: implement for multiple requests
                getDependencies(request);
            catch err
                % Buid a list of available signals for display
                list = getDependencies('available');
                str = [];
                for ii = 1:size(list,2)-1
                    str = [str list{ii} ', '];
                end
                % Return the list
                error(['One of the requested signal, cue, or feature '...
                    'name is unknown. Valid names are as follows: %s'],str)
            end

            
            % Find most suitable initial processor for that request
            [initProc,dep_list] = mObj.findInitProc(request,p);
            
            % Algorithm should proceed further even if the requested
            % processor already exists
            if isempty(dep_list)
                proceed = 1;
            end
            
            % The processing order is the reversed list of dependencies
            dep_list = fliplr(dep_list);

            
            
            % Former number of processors
            n_proc = size(mObj.Processors,1);
            
            % Number of new processors involved
            n_new_proc = size(dep_list,2);
            
            % Preallocation
            if isempty(mObj.Processors)
                if mObj.Data.isStereo
                    n_chan = 2;
                else
                    n_chan = 1;
                end
                mObj.Processors = cell(n_new_proc,n_chan);   
                mObj.InputList = cell(n_new_proc,n_chan);    % TO DO: Will have to be changed to account for multiple input features
                mObj.OutputList = cell(n_new_proc,n_chan);
            end
            
            
            % Initialize pointer to dependency 
            if size(initProc,2)==2
                % Need to refer to left and right chanel initial processors
                % and signals
                dep_sig_l = initProc{1}.Output;
                dep_sig_r = initProc{2}.Output;
                dep_proc_l = initProc{1};
                dep_proc_r = initProc{2};
            elseif size(initProc,2)==1
                % Only a single processor and signal (either mono, or
                % already a binaural feature)
                dep_sig = initProc.Output;
                dep_proc = initProc;
            else
                % Then processing starts from scratch, need to assess the
                % number of channels
                if mObj.Data.isStereo
                    dep_sig_l = mObj.Data.signal{1};
                    dep_sig_r = mObj.Data.signal{2};
                    dep_proc_l = [];
                    dep_proc_r = [];
                else
                    dep_sig = mObj.Data.signal{1};
                    dep_proc = [];
                end
            end
                
            % Processors instantiation and data object property population
            for ii = n_proc+1:n_proc+n_new_proc   
                
                proceed = 1;     % Initialize a flag to identify invalid requests (binaural representation requested on a mono signal)
                
                switch dep_list{ii-n_proc}
                    
                    case 'time'
                        % TO DO: Include actual time processor
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = preProc(p.fs,p);
%                             mObj.Processors{ii,2} = identityProc(p.fs);
                            % Generate new signals
                            sig_l = TimeDomainSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'time','Time domain signal',[],'left');
                            sig_r = TimeDomainSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'time','Time domain signal',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii} = preProc(p.fs,p);
                            % Generate a new signal
                            sig = TimeDomainSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'time','Time domain signal',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                                     
                    case 'framedSignal'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = framingProc(p.fs,p.fr_wname,p.fr_wSize,p.fr_hSize);
                            mObj.Processors{ii,2} = framingProc(p.fs,p.fr_wname,p.fr_wSize,p.fr_hSize);
                            % Generate new signals
                            sig_l = FramedSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,p.fr_wSize,mObj.Processors{ii,1}.FsHzIn,'framedSignal','Framed signal','left');
                            sig_r = FramedSignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,p.fr_wSize,mObj.Processors{ii,1}.FsHzIn,'framedSignal','Framed signal','right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii} = framingProc(p.fs,p.fr_wname,p.fr_wSize,p.fr_hSize);
                            % Generate a new signal
                            sig = FramedSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,p.fr_wSize,mObj.Processors{ii,1}.FsHzIn,'framedSignal','Framed signal','mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'gammatone'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            switch gamma_init
                                case 'cfHz'
                                    mObj.Processors{ii,1} = gammatoneProc(p.fs,[],[],[],[],p.gt_cfHz,p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                    mObj.Processors{ii,2} = gammatoneProc(p.fs,[],[],[],[],p.gt_cfHz,p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                   
                                case 'nChannels'
                                    mObj.Processors{ii,1} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,[],p.gt_nChannels,[],p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                    mObj.Processors{ii,2} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,[],p.gt_nChannels,[],p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                    
                                case 'standard'
                                    mObj.Processors{ii,1} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,p.gt_nERBs,[],[],p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                    mObj.Processors{ii,2} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,p.gt_nERBs,[],[],p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                            end
                            % Generate new signals
                            sig_l = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'gammatone',mObj.Processors{ii}.cfHz,'Gammatone filterbank output',[],'left');
                            sig_r = TimeFrequencySignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'gammatone',mObj.Processors{ii}.cfHz,'Gammatone filterbank output',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            switch gamma_init
                                case 'cfHz'
                                    mObj.Processors{ii,1} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,[],[],p.gt_cfHz,p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                case 'nChannels'
                                    mObj.Processors{ii,1} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,[],p.gt_nChannels,[],p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                                case 'standard'
                                    mObj.Processors{ii,1} = gammatoneProc(p.fs,p.gt_lowFreqHz,p.gt_highFreqHz,p.gt_nERBs,[],[],p.gt_bAlign,p.gt_nGamma,p.gt_bwERBs);
                            end
                            % Generate a new signal
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'gammatone',mObj.Processors{ii}.cfHz,'Gammatone filterbank output',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'innerhaircell'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = ihcProc(dep_proc_l.FsHzOut,p.ihc_method);
                            mObj.Processors{ii,2} = ihcProc(dep_proc_r.FsHzOut,p.ihc_method);
                            % Generate new signals
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Get the center frequencies from dependencies
                            sig_l = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'innerhaircell',cfHz,'Inner hair-cell envelope',[],'left');
                            sig_r = TimeFrequencySignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'innerhaircell',cfHz,'Inner hair-cell envelope',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii} = ihcProc(dep_proc.FsHzOut,p.ihc_method);
                            % Generate a new signal
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Get the center frequencies from dependencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'innerhaircell',cfHz,'Inner hair-cell envelope',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'ams_features'
                        if mObj.Data.isStereo
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Vector of center audio frequencies
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = modulationProc(dep_proc_l.FsHzOut,numel(cfHz),p.ams_cfHz,p.ams_nFilters,p.ams_lowFreqHz,p.ams_highFreqHz,p.ams_wname,p.ams_wSizeSec,p.ams_hSizeSec,p.ams_fbType,p.ams_dsRatio);
                            mObj.Processors{ii,2} = modulationProc(dep_proc_r.FsHzOut,numel(cfHz),p.ams_cfHz,p.ams_nFilters,p.ams_lowFreqHz,p.ams_highFreqHz,p.ams_wname,p.ams_wSizeSec,p.ams_hSizeSec,p.ams_fbType,p.ams_dsRatio);
                            % Generate new signals
                            modCfHz = mObj.Processors{ii,1}.modCfHz;            % Vector of center modulation frequencies
                            sig_l = ModulationSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'ams_features',cfHz,modCfHz,'Amplitude modulation spectrogram',[],'left');
                            sig_r = ModulationSignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'ams_features',cfHz,modCfHz,'Amplitude modulation spectrogram',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Vector of center audio frequencies
                            % Instantiate a processor
                            mObj.Processors{ii,1} = modulationProc(dep_proc.FsHzOut,numel(cfHz),p.ams_cfHz,p.ams_nFilters,p.ams_lowFreqHz,p.ams_highFreqHz,p.ams_wname,p.ams_wSizeSec,p.ams_hSizeSec,p.ams_fbType,p.ams_dsRatio);
                            % Generate a new signal
                            modCfHz = mObj.Processors{ii,1}.modCfHz;            % Vector of center modulation frequencies
                            sig = ModulationSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'ams_features',cfHz,modCfHz,'Amplitude modulation spectrogram',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        clear modCfHz cfHz
                        
                    case 'autocorrelation'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = autocorrelationProc(dep_proc_l.FsHzOut,p,mObj.use_mex);
                            mObj.Processors{ii,2} = autocorrelationProc(dep_proc_r.FsHzOut,p,mObj.use_mex);
                            % Generate new signals
                            lags = ((1:(2 * round(mObj.Processors{ii,1}.wSizeSec * p.fs * 0.5)-1))-1)/p.fs;
                            cfHz = dep_proc_l.getDependentParameter('cfHz');         % Vector of center frequencies
                            sig_l = CorrelationSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'autocorrelation',cfHz,lags,'Auto-correlation',[],'left');
                            sig_r = CorrelationSignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'autocorrelation',cfHz,lags,'Auto-correlation',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii,1} = autocorrelationProc(dep_proc.FsHzOut,p,mObj.use_mex);
                            % Generate a new signal
                            lags = ((1:(2 * round(mObj.Processors{ii,1}.wSizeSec * p.fs * 0.5)-1))-1)/p.fs;
                            cfHz = dep_proc.getDependentParameter('cfHz');         % Vector of center frequencies
                            sig = CorrelationSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'autocorrelation',cfHz,lags,'Auto-correlation',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        clear lags
                        
                    case 'pitch'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            lags = dep_sig_l.lags;
                            mObj.Processors{ii,1} = pitchProc(dep_proc_l.FsHzOut,lags,p);
                            mObj.Processors{ii,2} = pitchProc(dep_proc_r.FsHzOut,lags,p);
                            % Generate new signals
                            sig_l = FeatureSignal(mObj.Processors{ii,1}.FsHzOut,{'pitch','rawPitch','confidence'},mObj.Data.bufferSize_s,'pitch','Pitch estimation','left');
                            sig_r = FeatureSignal(mObj.Processors{ii,1}.FsHzOut,{'pitch','rawPitch','confidence'},mObj.Data.bufferSize_s,'pitch','Pitch estimation','left');
%                             sig_l = TimeDomainSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'pitch','Pitch estimation',[],'left');
%                             sig_r = TimeDomainSignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'pitch','Pitch estimation',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            lags = dep_sig.lags;
                            mObj.Processors{ii,1} = pitchProc(dep_proc.FsHzOut,lags,p);
                            % Generate a new signal
                            sig = FeatureSignal(mObj.Processors{ii,1}.FsHzOut,{'pitch','rawPitch','confidence'},mObj.Data.bufferSize_s,'pitch','Pitch estimation','mono');
%                             sig = TimeDomainSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'pitch','Pitch estimation',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'crosscorrelation'
                        % Check that two channels are available
                        if ~mObj.Data.isStereo
                            warning('Manager cannot instantiate a binaural cue extractor for a single-channel signal')
                            proceed = 0;
                        else
%                             mObj.Processors{ii,1} = crosscorrelationProc(p.fs,p);
                                
                            % TEMP:
                            mObj.Processors{ii,1} = crosscorrelationProc(dep_proc_l.FsHzOut,p,mObj.use_mex);

                            maxLag = ceil(mObj.Processors{ii,1}.maxDelaySec*dep_proc_l.FsHzOut);
                            lags = (-maxLag:maxLag)/dep_proc_l.FsHzOut;                           % Lags
                            cfHz = dep_proc_l.getDependentParameter('cfHz');        % Center frequencies 
                            sig = CorrelationSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'crosscorrelation',cfHz,lags,'Cross-correlation',[],'mono');
                            mObj.Data.addSignal(sig);
                            clear maxLag lags
                        end
                        
                    case 'crosscorrelation_feature'
                        % Check that two channels are available
                        if ~mObj.Data.isStereo
                            warning('Manager cannot instantiate a binaural cue extractor for a single-channel signal')
                            proceed = 0;
                        else
                            mObj.Processors{ii,1} = ccFeatureProc(dep_proc.FsHzOut,p.ccf_factor);

                            % Previous lag vector
                            lags = dep_sig.lags;
                            n_lags = size(lags,2);
                            
                            % Downsample this vector
                            origin = (n_lags+1)/2;
                            n_lags_ds = floor((origin-1)/p.ccf_factor);
                            lags_ds = lags(origin-n_lags_ds*p.ccf_factor:p.ccf_factor:origin+n_lags_ds*p.ccf_factor);
                            
                            % Center frequencies
                            cfHz = dep_proc_l.getDependentParameter('cfHz');        % Center frequencies 
                            
                            % Instantiate a new signal
                            sig = CorrelationSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'crosscorrelation_feature',cfHz,lags_ds,'Cross-correlation feature',[],'mono');
                            mObj.Data.addSignal(sig);
                            clear lags n_lags origin n_lags_ds lags_ds
                        end
                        
                    case 'ratemap'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = ratemapProc(dep_proc_l.FsHzOut,p,mObj.use_mex);
                            mObj.Processors{ii,2} = ratemapProc(dep_proc_r.FsHzOut,p,mObj.use_mex);
                            % Generate new signals
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Center frequencies
                            sig_l = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'ratemap',cfHz,'Ratemap',[],'left',p.rm_scaling);
                            sig_r = TimeFrequencySignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'ratemap',cfHz,'Ratemap',[],'right',p.rm_scaling);
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii,1} = ratemapProc(dep_proc.FsHzOut,p,mObj.use_mex);
                            % Generate a new signal
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'ratemap',cfHz,'Ratemap',[],'mono',p.rm_scaling);
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                                                
                    case 'onset_strength'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = onsetProc(dep_proc_l.FsHzOut,p);
                            mObj.Processors{ii,2} = onsetProc(dep_proc_r.FsHzOut,p);
                            % Generate new signals
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Center frequencies
                            sig_l = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'onset_strength',cfHz,'Onset strength',[],'left');
                            sig_r = TimeFrequencySignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'onset_strength',cfHz,'Onset strength',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii,1} = onsetProc(dep_proc.FsHzOut,p);
                            % Generate a new signal
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'onset_strength',cfHz,'Onset strength',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'offset_strength'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = offsetProc(dep_proc_l.FsHzOut,p);
                            mObj.Processors{ii,2} = offsetProc(dep_proc_r.FsHzOut,p);
                            % Generate new signals
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Center frequencies
                            sig_l = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'offset_strength',cfHz,'Offset strength',[],'left');
                            sig_r = TimeFrequencySignal(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'offset_strength',cfHz,'Offset strength',[],'right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii,1} = offsetProc(dep_proc.FsHzOut,p);
                            % Generate a new signal
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'offset_strength',cfHz,'Offset strength',[],'mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'onset_map'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = transientMapProc(dep_proc_l.FsHzOut,p);
                            mObj.Processors{ii,2} = transientMapProc(dep_proc_r.FsHzOut,p);
                            % Generate new signals
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Center frequencies
                            sig_l = BinaryMask(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'onset_map',cfHz,'Onset map',[],'left',dep_proc_l.Input);
                            sig_r = BinaryMask(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'onset_map',cfHz,'Onset map',[],'right',dep_proc_r.Input);
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii,1} = transientMapProc(dep_proc.FsHzOut,p);
                            % Generate a new signal
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = BinaryMask(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'onset_map',cfHz,'Onset map',[],'mono',dep_proc.Input);
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'offset_map'
                        if mObj.Data.isStereo
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = transientMapProc(dep_proc_l.FsHzOut,p);
                            mObj.Processors{ii,2} = transientMapProc(dep_proc_r.FsHzOut,p);
                            % Generate new signals
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Center frequencies
                            sig_l = BinaryMask(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'offset_map',cfHz,'Offset map',[],'left',dep_proc_l.Input);
                            sig_r = BinaryMask(mObj.Processors{ii,2}.FsHzOut,mObj.Data.bufferSize_s,'offset_map',cfHz,'Offset map',[],'right',dep_proc_r.Input);
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Instantiate a processor
                            mObj.Processors{ii,1} = transientMapProc(dep_proc.FsHzOut,p);
                            % Generate a new signal
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = BinaryMask(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'offset_map',cfHz,'Offset map',[],'mono',dep_proc.Input);
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'spectral_features'
                        if mObj.Data.isStereo
                            % Get the center frequencies from dependent processors
                            cfHz = dep_proc_l.getDependentParameter('cfHz');
                            % Instantiate left and right ear processors
                            mObj.Processors{ii,1} = spectralFeaturesProc(dep_proc_l.FsHzOut,cfHz,p.sf_requests,p.sf_br_cf,p.sf_ro_perc);
                            mObj.Processors{ii,2} = spectralFeaturesProc(dep_proc_r.FsHzOut,cfHz,p.sf_requests,p.sf_br_cf,p.sf_ro_perc);
                            % Generate new signals
%                             sig_l = SpectralFeaturesSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Processors{ii,1}.requestList,mObj.Data.bufferSize_s,'spectral_features','Spectral Features','left');
%                             sig_r = SpectralFeaturesSignal(mObj.Processors{ii,2}.FsHzOut,mObj.Processors{ii,2}.requestList,mObj.Data.bufferSize_s,'spectral_features','Spectral Features','right');
                            sig_l = FeatureSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Processors{ii,1}.requestList,mObj.Data.bufferSize_s,'spectral_features','Spectral Features','left');
                            sig_r = FeatureSignal(mObj.Processors{ii,2}.FsHzOut,mObj.Processors{ii,2}.requestList,mObj.Data.bufferSize_s,'spectral_features','Spectral Features','right');
                            % Add the signals to the data object
                            mObj.Data.addSignal(sig_l);
                            mObj.Data.addSignal(sig_r)
                        else
                            % Get the center frequencies from dependent processors
                            cfHz = dep_proc.getDependentParameter('cfHz');
                            % Instantiate a processor
                            mObj.Processors{ii,1} = spectralFeaturesProc(dep_proc.FsHzOut,cfHz,p.sf_requests,p.sf_br_cf,p.sf_ro_perc);
                            % Generate a new signal
%                             sig = SpectralFeaturesSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Processors{ii,1}.requestList,mObj.Data.bufferSize_s,'spectral_features','Spectral Features','mono');
                            sig = FeatureSignal(mObj.Processors{ii,1}.FsHzOut,mObj.Processors{ii,1}.requestList,mObj.Data.bufferSize_s,'spectral_features','Spectral Features','mono');
                            % Add signal to the data object
                            mObj.Data.addSignal(sig);
                        end
                        
                        
                        
                    case 'ild'
                        % Check that two channels are available
                        if ~mObj.Data.isStereo
                            warning('Manager cannot instantiate a binaural cue extractor for a single-channel signal')
                            proceed = 0;
                        else
                            mObj.Processors{ii,1} = ildProc(dep_proc_l.FsHzOut,p);
                            cfHz = dep_proc_l.getDependentParameter('cfHz');    % Center frequencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'ild',cfHz,'Interaural Level Difference',[],'mono');
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'ic'
                        if ~mObj.Data.isStereo
                            warning('Manager cannot instantiate a binaural cue extractor for a single-channel signal')
                            proceed = 0;
                        else
                            mObj.Processors{ii,1} = icProc(dep_proc.FsHzOut,p);
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'ic',cfHz,'Interaural correlation',[],'mono');
                            mObj.Data.addSignal(sig);
                        end
                        
                    case 'itd'
                        if ~mObj.Data.isStereo
                            warning('Manager cannot instantiate a binaural cue extractor for a single-channel signal')
                            proceed = 0;
                        else
                            mObj.Processors{ii,1} = itdProc(dep_proc.FsHzOut,p);
                            cfHz = dep_proc.getDependentParameter('cfHz');    % Center frequencies
                            sig = TimeFrequencySignal(mObj.Processors{ii,1}.FsHzOut,mObj.Data.bufferSize_s,'itd',cfHz,'Interaural Time Difference',[],'mono');
                            mObj.Data.addSignal(sig);
                        end
                        
                    % TO DO: Populate that list further
                    
                    % N.B: No need for "otherwise" case once complete
                    
                    otherwise
                        error('%s is not supported at the moment',...
                            dep_list{ii+1});
                end
                
                if ~isempty(mObj.Processors{ii})
                
                    % Add input/output pointers, dependencies, and update dependencies.
                    % Three possible scenarios:

                    if mObj.Processors{ii}.isBinaural

                        if ~mObj.Processors{ii}.hasTwoOutputs
                            % 1-Then there are two inputs (left&right) and one output
                            mObj.InputList{ii,1} = dep_sig_l;
                            mObj.InputList{ii,2} = dep_sig_r;
                            mObj.OutputList{ii,1} = sig;
                            mObj.OutputList{ii,2} = [];

                            mObj.Processors{ii}.Input{1} = dep_sig_l;
                            mObj.Processors{ii}.Input{2} = dep_sig_r;
                            mObj.Processors{ii}.Output = sig;

                            mObj.Processors{ii,1}.Dependencies = {dep_proc_l,dep_proc_r};
                            dep_sig = sig;
                            dep_proc = mObj.Processors{ii};
                        else
                            if exist('sig','var')&&strcmp(sig.Channel,'mono')
                                % 1bis - Two inputs and two outputs
                                mObj.InputList{ii,1} = dep_sig;
                                mObj.OutputList{ii,1} = sig;

                                mObj.Processors{ii}.Input = dep_sig;
                                mObj.Processors{ii}.Output = sig;

                                mObj.Processors{ii,1}.Dependencies = {dep_proc};
                                dep_sig = sig;
                                dep_proc = mObj.Processors{ii};
                            else
                                % 1bis - Two inputs and two outputs
                                mObj.InputList{ii,1} = dep_sig_l;
                                mObj.InputList{ii,2} = dep_sig_r;
                                mObj.OutputList{ii,1} = sig_l;
                                mObj.OutputList{ii,2} = sig_r;

                                mObj.Processors{ii}.Input{1} = dep_sig_l;
                                mObj.Processors{ii}.Input{2} = dep_sig_r;
%                                 mObj.Processors{ii}.Output{1} = sig_l;
%                                 mObj.Processors{ii}.Output{2} = sig_r;
                                mObj.Processors{ii}.Output = sig_l;
                                


                                mObj.Processors{ii,1}.Dependencies = {dep_proc_l,dep_proc_r};
                                dep_sig_l = sig_l;
                                dep_sig_r = sig_r;
                                dep_proc_l = mObj.Processors{ii};
                                dep_proc_r = mObj.Processors{ii};
                            end
                        end
                    elseif exist('sig','var')&&strcmp(sig.Channel,'mono') && proceed

                        % 2-Then there is a single input and single output
                        mObj.InputList{ii,1} = dep_sig;
                        mObj.OutputList{ii,1} = sig;

                        mObj.Processors{ii}.Input = dep_sig;
                        mObj.Processors{ii}.Output = sig;

                        mObj.Processors{ii}.Dependencies = {dep_proc};
                        dep_sig = sig;
                        dep_proc = mObj.Processors{ii};

                    elseif ~proceed

                        % Do nothing, this request is invalid and should be
                        % skipped

                    else

                        % 3-Else there are two inputs and two outputs
                        mObj.InputList{ii,1} = dep_sig_l;
                        mObj.InputList{ii,2} = dep_sig_r;
                        mObj.OutputList{ii,1} = sig_l;
                        mObj.OutputList{ii,2} = sig_r;

                        mObj.Processors{ii,1}.Input = dep_sig_l;
                        mObj.Processors{ii,2}.Input = dep_sig_r;
                        mObj.Processors{ii,1}.Output = sig_l;
                        mObj.Processors{ii,2}.Output = sig_r;

                        mObj.Processors{ii,1}.Dependencies = {dep_proc_l};
                        mObj.Processors{ii,2}.Dependencies = {dep_proc_r};
                        dep_sig_l = sig_l;
                        dep_sig_r = sig_r;
                        dep_proc_l = mObj.Processors{ii,1};
                        dep_proc_r = mObj.Processors{ii,2};

                    end
                    
                else
                    % Then the processor was not instantiated as the
                    % request was invalid, exit the for loop
                    break
                end

                
                % Clear temporary handles to ensure no inconsistencies 
                clear sig sig_l sig_r
                
            end
            
            % The mapping at this point is linear
            mObj.Map(n_proc+1:n_proc+n_new_proc) = n_proc+1:n_proc+n_new_proc;
            
            % Provide the user with a pointer to the requested signal
            if nargout>0 && proceed
                if ~isempty(dep_list)
                    if size(mObj.Processors,2)==2
                        if isempty(mObj.Processors{n_proc+n_new_proc,2})
                            out = mObj.Processors{n_proc+n_new_proc,1}.Output;
                        else
                            out{1,1} = mObj.Processors{n_proc+n_new_proc,1}.Output;
                            out{1,2} = mObj.Processors{n_proc+n_new_proc,2}.Output;
                        end
                    else
                        out = mObj.Processors{n_proc+n_new_proc,1}.Output;
                    end
                else
                    % Else no new processor was added as the requested one
                    % already existed
                    if size(initProc,2)==2
                        out{1,1} = dep_sig_l;
                        out{1,2} = dep_sig_r;
                    else
                        out = dep_sig;
                    end
                end
            elseif ~proceed
                warning('The request was invalid, returning an empty handle')
                out = [];
            end
            
        end
        
        function [hProc,list] = findInitProc(mObj,request,p)
            %findInitProc   Find an initial compatible processor for a new
            %               request
            %
            %USAGE:
            %         hProc = mObj.findInitProc(request,p)
            %  [hProc,list] = mObj.findInitProc(request,p)
            %
            %INPUT PARAMETERS
            %    mObj : Manager instance
            % request : Requested signal name
            %       p : Parameter structure associated to the request
            %
            %OUTPUT PARAMETERS
            %   hProc : Handle to the highest processor in the processing 
            %           chain that is compatible with the provided
            %           parameters. In case two instances exist for the
            %           processor for a stereo signal, hProc is a cell
            %           array of the form {'leftEarProc','rightEarProc'}
            %    list : List of signal names that need to be computed,
            %           starting from the output of hProc, to obtain the
            %           request
        
            % Input parameter checking
            if nargin<3 || isempty(p)
                % Initialize parameter structure
                p = struct;
            end
            if ~isfield(p,'fs')
                % Add sampling frequency to the parameter structure
                p.fs = mObj.Data.signal{1}.FsHz;
            end
            % Add default values for parameters not explicitly defined in p
            p = parseParameters(p);
        
            % Try/Catch to check that the request is valid
            try
                getDependencies(request);
            catch err
                % Buid a list of available signals for display
                list = getDependencies('available');
                str = [];
                for ii = 1:size(list,2)-1
                    str = [str list{ii} ', '];
                end
                % Return the list
                error(['The requested signal, %s is unknown. '...
                    'Valid names are as follows: %s'],request,str)
            end
            
            % Get the full list of dependencies corresponding to the request
            if ~strcmp(request,'time')
                dep_list = [request getDependencies(request)];
            else
                % Time is a special case as it is listed as its own dependency
                dep_list = getDependencies(request);
            end
            
            
            % Initialization of while loop
            ii = 1;
            dep = signal2procName(dep_list{ii});
            hProc = mObj.hasProcessor(dep,p);
            list = {};
            
            % Looping until we find a suitable processor in the list of
            % dependency
            while hProc == 0 && ii<size(dep_list,2)
                
                % Then we will need to re-compute that signal
                list = [list dep_list{ii}];
                
                % Move on to next level of dependency
                ii = ii + 1;
                dep = signal2procName(dep_list{ii});
                hProc = mObj.hasProcessor(dep,p);
                
            end
            
            if hProc == 0
                % Then all the signals need recomputation, including time
                list = [list dep_list{end}];
                
                % Return a empty handle
                hProc = [];
            end
            
            % If the processor found operates on the left channel of a stereo
            % signal, we need to find its twin processor in charge of the
            % right channel
            if ~isempty(hProc) && strcmp(hProc.Output.Channel,'left')
                
                % Then repeat the same loop, but specifying the "other"
                % channel
                Channel = 'right';
                
                % Initialization of while loop
                ii = 1;
                dep = signal2procName(dep_list{ii});
                hProc2 = mObj.hasProcessor(dep,p,Channel);
                list = {};

                % Looping until we find a suitable processor in the list of
                % dependency
                while hProc2 == 0 && ii<size(dep_list,2)

                    % Then we will need to re-compute that signal
                    list = [list dep_list{ii}];

                    % Move on to next level of dependency
                    ii = ii + 1;
                    dep = signal2procName(dep_list{ii});
                    hProc2 = mObj.hasProcessor(dep,p,Channel);

                end
                
                % Quick check that both found processor have the same task
                % (else there was probably an issue somewhere in channel
                % attribution)
%                 if ~strcmp(class(hProc),class(hProc2))
%                     error('Found different processors for left and right channels.')
%                 end
                
                % Put results in a cell array
                hProc = {hProc hProc2};
                
            end
            
        end
        
        function reset(mObj)
            %reset  Reset the internal states of all instantiated
            %processors
            %
            %USAGE:
            %  mObj.reset
            %
            %INPUT ARGUMENTS
            %  mObj : Manager instance
            
            % Is the manager working on a binaural signal?
            if size(mObj.Processors,2)==2
                
                % Then loop over the processors
                for ii = 1:size(mObj.Processors,1)
                   
                    % There should always be a processor for left/mono
                    mObj.Processors{ii,1}.reset;
                    
                    % Though there might not be a right-channel processor
                    if isa(mObj.Processors{ii,2},'Processor')
                        mObj.Processors{ii,2}.reset;
                    end
                        
                end
                
            else
            
                % Loop over the processors
                for ii = 1:size(mObj.Processors,1)
                    
                    mObj.Processors{ii,1}.reset;
                        
                end
            end
            
        end
        
        
    end
    
    
end