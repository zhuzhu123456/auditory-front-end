function  parameterHelper(procName)
%parameterHelper     Extensive and user friendly listing of parameters involved
%                    in the Two!Ears Auditory Front-End.
%
%USAGE:
%    parameterHelper



% Load the parameter info file
% path = fileparts(mfilename('fullpath'));
% load([path filesep 'parameterInfo.mat'])
% 
% % List the categories
% cats = fieldnames(pInfo);
% cats = sort(cats);

if nargin == 0 || isempty(procName)
    % Display the list of processors with an introductory header
    
    % Get a list of presumably valid processors
    procList = Processor.processorList;
    
    % Access their description
    procDescription = cell(size(procList));
    for ii = 1:size(procList,1)
        try
            pInfo = feval([procList{ii} '.getProcessorInfo']);
			procDescription{ii} = pInfo.label;
        catch
            procDescription{ii} = [];
        end
    end
    
    % Remove invalid elements
    procList = procList(~cellfun('isempty',procDescription));
    procDescription = procDescription(~cellfun('isempty',procDescription));
    
    % Get an index for alphabetical ordering
    [~,idx] = sort(procDescription);
    
    
    % Display header
    fprintf('\nParameter handling in the Two!Ears Auditory Front-End')
    fprintf('\n-------------------------------------------------\n')
    fprintf(['The extraction of various auditory representations '...
        'performed by the Two!Ears auditory front-end (AFE) software involves many parameters.\n'])
    fprintf('Each parameter is given a unique name and a default value. ')
    fprintf(['When placing a request for Two!Ears auditory front-end processing that\n'...
        'uses one or more non-default parameters, a specific structure of non-default parameters needs to be provided as input.\n'])
    fprintf('Such structure can be generated from <a href="matlab: help genParStruct">genParStruct</a>, using pairs of parameter name and chosen value as inputs.\n' )
    fprintf('\nParameters names for each processors are listed below:\n')

    % Display the categories
%     for ii = 1:size(cats,1)
%         category = cats{ii};
%         link = ['<a href="matlab:parameterHelper(''' category ''')">'];
%         fprintf(['\t' link pInfo.(cats{ii}).label '</a>\n'])
%     end
    
    % Display the categories
    for ii = 1:size(idx,1)
        hLink = ['<a href="matlab:parameterHelper(''' procList{idx(ii)} ''')">'];
        fprintf(['\t' hLink procDescription{idx(ii)} '</a>\n'])
    end

    fprintf('\n')
else
    
    % Load the parameter names, default values and description 
    try 
        [names,values,description] = feval([procName '.getParameterInfo']);
    catch
        warning(['There is no %s processor, or its getParameterInfo static method '...
                 'is not implemented.'])
    end
    
    % TODO: Do something specific for processors without parameters?
    
    % Find appropriate columns widths
    name_size = 4;  % Size of string 'Name'
    for ii = 1:size(names,2)
        name_size = max(name_size,size(names{ii},2));
    end
    
    valueStr = cell(1,size(names,2));
    val_size = 7;   % Size of string 'Default'
    
    % Text formatting for the parameter default value
    for ii = 1:size(names,2)
        if iscell(values{ii})
            % Then it's multiple strings concatenated in a cell array, add braces
            val = '{';
            for jj = 1:size(values{ii},2)-1  % TODO: Use strjoin instead?
                val = [val '''' values{ii}{jj} ''',']; %#ok<AGROW>
            end
            valueStr{ii} = [val '''' values{ii}{jj+1} '''}'];
        elseif ischar(values{ii})
            % Then it's a single string
            valueStr{ii} = ['''' values{ii} ''''];
        elseif size(values{ii},2)>1
            % Then it's an numerical array
            val = ['['];
            for jj = 1:size(values{ii},2)-1
                val = [val num2str(values{ii}(jj)) ' '];
            end
            valueStr{ii} = [val num2str(values{ii}(jj+1)) ']'];
        else
            % It's a single numeral
            valueStr{ii} = num2str(values{ii});
        end

        % Keep track of larger string for table formatting
        val_size = max(val_size,size(values{ii},2));
    end
    
    % Display a header
    if ~isempty(names)
        fprintf(['  %-' int2str(name_size+2) 's  %-' int2str(val_size+1) 's  %-s\n'],'Name','Default','Description')
        fprintf(['  %-' int2str(name_size+2) 's  %-' int2str(val_size+1) 's  %-s\n'],'----','-------','-----------')
    end

    for ii = 1:size(names,2)
        % Display on command window
        fprintf(['  %-' int2str(name_size+2) 's  %-' int2str(val_size+1) 's  %-s\n'],...
                names{ii},valueStr{ii},description{ii})
    end
    fprintf('\n')
    
    
    
    
%     if isfield(pInfo,cat)
%         
%         % Get the parameter names for this category
%         names = fieldnames(pInfo.(cat));
%         
%         % Remove the category label
%         names = names(2:end);   
%         
%         % Make names an empty array if it is an empty cell (for processors
%         % with no parameters)
%         if isempty(names)
%             names = [];
%         end
%         
%         % Find appropriate columns widths
%         name_size = 4;  % Size of string 'Name'
%         
%         for ii = 1:size(names,1)
%             name_size = max(name_size,size(names{ii},2));
%         end
%         
%         
%         
%         
%         % Display the category name and label
%         if ~isempty(names)
%             fprintf(['\n' pInfo.(cat).label ' parameters:\n\n'])
%         else
%             fprintf(['\n' pInfo.(cat).label ' processors have no parameters of their own.\n\n'])
%         end
%         
%         
%         % Display a list of parameters for this category
%         
%         % Text formatting for the parameter default value
%         value = cell(size(names,1),1);
%         val_size = 7;   % Size of string 'Default'
%         for ii = 1:size(names,1)
%             if iscell(pInfo.(cat).(names{ii}).value)
%                 % Then it's multiple strings concatenated in a cell array
%                 val = ['{'];
%                 for jj = 1:size(pInfo.(cat).(names{ii}).value,2)-1
%                     val = [val '''' pInfo.(cat).(names{ii}).value{jj} ''','];
%                 end
%                 value{ii} = [val '''' pInfo.(cat).(names{ii}).value{jj+1} '''}'];
%             elseif ischar(pInfo.(cat).(names{ii}).value)
%                 % Then it's a single string
%                 value{ii} = ['''' pInfo.(cat).(names{ii}).value ''''];
%             elseif size(pInfo.(cat).(names{ii}).value,2)>1
%                 % Then it's an numerical array
%                 val = ['['];
%                 for jj = 1:size(pInfo.(cat).(names{ii}).value,2)-1
%                     val = [val num2str(pInfo.(cat).(names{ii}).value(jj)) ' '];
%                 end
%                 value{ii} = [val num2str(pInfo.(cat).(names{ii}).value(jj+1)) ']'];
%             else
%                 % It's a single numeral
%                 value{ii} = num2str(pInfo.(cat).(names{ii}).value);
%             end
%             
%             % Keep track of larger string for table formatting
%             val_size = max(val_size,size(value{ii},2));
%             
%         end
%            
%         % Display a header
%         if ~isempty(names)
%             fprintf(['  %-' int2str(name_size+2) 's  %-' int2str(val_size+1) 's  %-s\n'],'Name','Default','Description')
%             fprintf(['  %-' int2str(name_size+2) 's  %-' int2str(val_size+1) 's  %-s\n'],'----','-------','-----------')
%         end
%         
%         for ii = 1:size(names,1)
%             % Display on command window
%             fprintf(['  %-' int2str(name_size+2) 's  %-' int2str(val_size+1) 's  %-s\n'],names{ii},value{ii},pInfo.(cat).(names{ii}).description)
%         end
%         fprintf('\n')
%     end
end
    
