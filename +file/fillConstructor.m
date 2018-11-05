function fcstr = fillConstructor(name, parentname, defaults, propnames, props, namespace)
caps = upper(name);
fcnbody = strjoin({['% ' caps ' Constructor for ' name] ...
    ['%     obj = ' caps '(parentname1,parentvalue1,..,parentvalueN,parentargN,name1,value1,...,nameN,valueN)'] ...
    }, newline);

txt = fillParamDocs(propnames, props);
if ~isempty(txt)
    fcnbody = [fcnbody newline txt];
end

txt = fillBody(parentname, defaults, propnames, props, namespace);
if ~isempty(txt)
    fcnbody = [fcnbody newline txt];
end

fcnbody = strjoin({fcnbody,...
    ['if strcmp(class(obj), ''types.', namespace.name, '.', name, ''')'],...
    '    types.util.checkUnset(obj, unique(varargin(1:2:end)));',...
    'end'}, newline);
fcstr = strjoin({...
    ['function obj = ' name '(varargin)']...
    file.addSpaces(fcnbody, 4)...
    'end'}, newline);
end

function fdfp = fillDocFromProp(prop, propnm)
if ischar(prop)
    fdfp = prop;
elseif isstruct(prop)
    fnm = fieldnames(prop);
    subp = '';
    for i=1:length(fnm)
        nm = fnm{i};
        subpropl = file.addSpaces(fillDocFromProp(prop.(nm), nm), 4);
        subp = [subp newline subpropl];
    end
    fdfp = ['table/struct of vectors/struct array/containers.Map of vectors with values:' newline subp];
elseif isa(prop, 'file.Attribute')
    fdfp = prop.dtype;
    if isa(fdfp, 'java.util.HashMap')
        switch fdfp.get('reftype')
            case 'region'
                reftypenm = 'region';
            case 'object'
                reftypenm = 'object';
            otherwise
                error('Invalid reftype found whilst filling Constructor prop docs.');
        end
        fdfp = ['ref to ' fdfp.get('target_type') ' ' reftypenm];
    end
elseif isa(prop, 'java.util.HashMap')
    switch prop.get('reftype')
        case 'region'
            reftypenm = 'region';
        case 'object'
            reftypenm = 'object';
        otherwise
            error('Invalid reftype found whilst filling Constructor prop docs.');
    end
    fdfp = ['ref to ' prop.get('target_type') ' ' reftypenm];
elseif isa(prop, 'file.Dataset') && isempty(prop.type)
    fdfp = fillDocFromProp(prop.dtype);
elseif isempty(prop.type)
    fdfp = 'types.untyped.Set';
else
    fdfp = prop.type;
end
if nargin >= 2
    fdfp = ['% ' propnm ' = ' fdfp];
end
end

function fcstr = fillParamDocs(names, props)
fcstr = '';
if isempty(names)
    return;
end

fcstrlist = cell(length(names), 1);
for i=1:length(names)
    nm = names{i};
    prop = props(nm);
    fcstrlist{i} = fillDocFromProp(prop, nm);
end
fcstr = strjoin(fcstrlist, newline);
end

function bodystr = fillBody(pname, defaults, names, props, namespace)
if isempty(defaults)
    bodystr = '';
else
    usmap = containers.Map;
    for i=1:length(defaults)
        nm = defaults{i};
        if strcmp(props(nm).dtype, 'char')
            usmap(nm) = ['''' props(nm).value ''''];
        else
            usmap(nm) = [props(nm).dtype '(' props(nm).value ')'];
        end
    end
    kwargs = io.map2kwargs(usmap);
    bodystr = ['varargin = [{' misc.cellPrettyPrint(kwargs) '} varargin];' newline];
end
bodystr = [bodystr 'obj = obj@' pname '(varargin{:});'];

if isempty(names)
    return;
end

constrained = false(size(names));
anon = false(size(names));
isattr = false(size(names));
typenames = repmat({''}, size(names));
varnames = repmat({''}, size(names));
for i=1:length(names)
    nm = names{i};
    prop = props(nm);
    
    if isa(prop, 'file.Group') || isa(prop, 'file.Dataset')
        constrained(i) = prop.isConstrainedSet;
        anon(i) = ~prop.isConstrainedSet && isempty(prop.name);
        
        if ~isempty(prop.type)
            pc_namespace = namespace.getNamespace(prop.type);
            varnames{i} = prop.type;
            if ~isempty(pc_namespace)
                typenames{i} = ['types.' pc_namespace.name '.' prop.type];
            end
        end
    elseif isa(prop, 'file.Attribute')
        isattr(i) = true;
    end
end

%warn for missing namespaces/property types
warnmsg = ['`' pname '`''s constructor is unable to check for type `%1$s` ' ...
    'because its namespace or type specifier could not be found.  Try generating ' ...
    'the namespace or class definition for type `%1$s` or fix its schema.'];

invalid = cellfun('isempty', typenames);
invalidWarn = invalid & (constrained | anon) & ~isattr;
invalidVars = varnames(invalidWarn);
for i=1:length(invalidVars)
    warning(warnmsg, invalidVars{i});
end
varnames = lower(varnames);

%we delete the entry in varargin such that any conflicts do not show up in inputParser
deleteFromVars = 'varargin([ivarargin ivarargin+1]) = [];';
%if constrained/anon sets exist, then check for nonstandard parameters and add as
%container.map
constrainedTypes = typenames(constrained & ~invalid);
constrainedVars = varnames(constrained & ~invalid);
methodCalls = strcat('[obj.', constrainedVars, ',ivarargin] = ',...
    ' types.util.parseConstrained(''', pname, ''', ''',...
    constrainedTypes, ''', varargin{:});');
fullBody = cell(length(methodCalls) * 2,1);
fullBody(1:2:end) = methodCalls;
fullBody(2:2:end) = {deleteFromVars};
fullBody = strjoin(fullBody, newline);
bodystr(end+1:end+length(fullBody)+1) = [newline fullBody];

%if anonymous values exist, then check for nonstandard parameters and add
%as Anon

anonTypes = typenames(anon & ~invalid);
anonVars = varnames(anon & ~invalid);
methodCalls = strcat('[obj.', anonVars, ',ivarargin] = ',...
    ' types.util.parseAnon(''', anonTypes, ''', varargin{:});');
fullBody = cell(length(methodCalls) * 2,1);
fullBody(1:2:end) = methodCalls;
fullBody(2:2:end) = {deleteFromVars};
fullBody = strjoin(fullBody, newline);
bodystr(end+1:end+length(fullBody)+1) = [newline fullBody];

parser = {...
    'p = inputParser;',...
    'p.KeepUnmatched = true;',...
    'p.PartialMatching = false;',...
    'p.StructExpand = false;'};

names = names(~constrained & ~anon);
defaults = cell(size(names));
for i=1:length(names)
    prop = props(names{i});
    if isa(prop, 'file.Group') && (prop.hasAnonData || prop.hasAnonGroups)
        defaults{i} = 'types.untyped.Set()';
    else
        defaults{i} = '[]';
    end
end
% add parameters
parser = [parser, strcat('addParameter(p, ''', names, ''', ', defaults,');')];
% parse
parser = [parser, {'parse(p, varargin{:});'}];
% get results
parser = [parser, strcat('obj.', names, ' = p.Results.', names, ';')];
parser = strjoin(parser, newline);
bodystr(end+1:end+length(parser)+1) = [newline parser];
end