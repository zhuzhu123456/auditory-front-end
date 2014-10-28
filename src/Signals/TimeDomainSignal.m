classdef TimeDomainSignal < Signal
    
    properties
        % Only inherited properties
    end
    
    methods
        function sObj = TimeDomainSignal(fs,bufferSize_s,name,label,data,channel)
            %TimeDomainSignal       Constructor for the "time domain signal"
            %                       children signal class
            %
            %USAGE
            %     sObj = TimeDomainSignal(fs)
            %     sObj = TimeDomainSignal(fs,name,label)
            %     sObj = TimeDomainSignal(fs,name,label,data,channel)
            %
            %INPUT ARGUMENTS
            %       fs : Sampling frequency (Hz)
            %     name : Formal name for the signal (default: name =
            %            'time')
            %    label : Label for the signal, to be used in e.g. figures
            %            (default: label = 'Waveform')
            %     data : Vector of amplitudes to construct an object from
            %            existing data
            %   channel : Flag indicating 'left', 'right', or 'mono'
            %            (default: channel = 'mono')
            
            %
            %OUTPUT ARGUMENT
            %     sObj : Time domain signal object inheriting the signal class
            
            sObj = sObj@Signal( fs, bufferSize_s, 1 );
            
            if nargin>0  % Failproof for Matlab empty calls
            
            % Check input arguments
            if nargin<6; channel = 'mono'; end
            if nargin<5; data = []; end
            if nargin<4||isempty(label); label = 'Waveform'; end
            if nargin<3||isempty(name); name = 'time'; end
            %if nargin<1; fs = []; end
            
            % Check dimensionality of data if it was provided
            if ~isempty(data) && min(size(data))>1
                error(['The data used to instantiate this object should be a' ...
                    'single vector of amplitude values'])
            end

            % Format data to a column vector
            data = data(:);
            
            % Populate object properties
            populateProperties(sObj,'Label',label,'Name',name,...
                'Dimensions','nSamples x 1');
            sObj.setData( data );
            sObj.Channel = channel;
            
            end
        end
       
        function h = plot(sObj,h0,p)
            %plot       This method plots the data from a time domain
            %           signal object
            %
            %USAGE
            %       sObj.plot
            %       sObj.plot(h_prev,p)
            %       h = sObj.plot(...)
            %
            %INPUT ARGUMENT
            %  h_prev : Handle to an already existing figure or subplot
            %           where the new plot should be placed
            %       p : Structure of non-default plot parameters (generated
            %           from genParStruct.m)
            %
            %OUTPUT ARGUMENT
            %       h : Handle to the newly created figure
            
            if ~isempty(sObj.Data)
            
                % Manage handles
                if nargin < 2 || isempty(h0)
                        h = figure;             % Generate a new figure
                    elseif get(h0,'parent')~=0
                        % Then it's a subplot
                        figure(get(h0,'parent')),subplot(h0)
                        h = h0;
                    else
                        figure(h0)
                        h = h0;
                end
                
                % Manage plot parameters
                if nargin < 3 || isempty(p) 
                    % Get default plotting parameters
                    p = getDefaultParameters([],'plotting');
                else
                    p.fs = sObj.FsHz;   % Add the sampling frequency to satisfy parseParameters
                    p = parseParameters(p);
                end

                % Generate a time axis
                t = 0:1/sObj.FsHz:(length(sObj.Data(:))-1)/sObj.FsHz;

                % Set up a title (include channel in the title)
                if ~strcmp(sObj.Channel,'mono')
                    pTitle = [sObj.Label ' - ' sObj.Channel];
                else
                    pTitle = sObj.Label;
                end
                
                % Plot
                plot(t,sObj.Data(:),'color',p.color,'linewidth',p.linewidth_s)
                xlabel('Time (s)','fontsize',p.fsize_label,'fontname',p.ftype)
                ylabel('Amplitude','fontsize',p.fsize_label,'fontname',p.ftype)
                title(pTitle,'fontsize',p.fsize_title,'fontname',p.ftype)
                set(gca,'fontsize',p.fsize_axes,'fontname',p.ftype)
                
                % Center the waveform
                m = max(abs(sObj.Data(:)));
                set(gca,'XLim',[t(1) t(end)],'YLim',[-1.1*m 1.1*m])
            
            else
                warning('This is an empty signal, cannot be plotted')
            end
                
            
        end
        
        function play(sObj)
            %play       Playback the audio from a time domain signal
            %
            %USAGE
            %   sObj.play()
            %
            %INPUT ARGUMENTS
            %   sObj : Time domain signal object
            
            sound(sObj.Data(:),sObj.FsHz)
            
        end
        
    end
end