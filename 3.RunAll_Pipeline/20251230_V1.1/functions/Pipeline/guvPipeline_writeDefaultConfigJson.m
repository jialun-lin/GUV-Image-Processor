function guvPipeline_writeDefaultConfigJson(jsonPath)
%GUVPIPELINE_WRITEDEFAULTCONFIGJSON 将 guvPipeline_configDefault() 写出为完整 JSON
% =========================================================================
% 目的：
%   - 你要求 JSON 字段与 guvPipeline_configDefault.m 保持一致（不仅包含新增字段）。
%   - JSON 不支持注释，因此“备注细节”仍以 guvPipeline_configDefault.m 为准。
%   - 建议工作流：用户先打开 configDefault 看说明，再编辑 JSON 做批量运行。
%
% 用法：
%   guvPipeline_writeDefaultConfigJson('.../guvPipeline_config.json')

    if nargin < 1 || isempty(jsonPath)
        jsonPath = fullfile(pwd, 'guvPipeline_config.json');
    end

    Cfg = guvPipeline_configDefault();

    % 若 configDefault 含路径字段，仅作为占位；真正运行时会被入口参数覆盖
    if ~isfield(Cfg,'ND2Path'), Cfg.ND2Path = ''; end
    if ~isfield(Cfg,'OutRoot'), Cfg.OutRoot = ''; end

    % 写出 JSON（MATLAB jsonencode 不输出缩进；这里做轻量美化）
    txt = jsonencode(Cfg);
    txt = localPrettyJson(txt);

    [outDir,~,~] = fileparts(jsonPath);
    if ~isempty(outDir) && ~exist(outDir,'dir')
        mkdir(outDir);
    end

    fid = fopen(jsonPath, 'w');
    if fid < 0
        error('无法写入 JSON：%s', jsonPath);
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function s = localPrettyJson(s)
% 轻量 JSON 格式化（避免依赖第三方库）
    indent = 0;
    out = strings(0,1);
    inStr = false;
    esc = false;
    for i = 1:strlength(string(s))
        ch = extractBetween(string(s), i, i);
        ch = char(ch);
        if ch == '"' && ~esc
            inStr = ~inStr;
        end
        if ~inStr
            if ch == '{' || ch == '['
                indent = indent + 1;
                out(end+1) = string(ch); %#ok<AGROW>
                out(end+1) = newline + repmat("  ", 1, indent); %#ok<AGROW>
                continue;
            elseif ch == '}' || ch == ']'
                indent = indent - 1;
                out(end+1) = newline + repmat("  ", 1, indent) + string(ch); %#ok<AGROW>
                continue;
            elseif ch == ','
                out(end+1) = string(ch); %#ok<AGROW>
                out(end+1) = newline + repmat("  ", 1, indent); %#ok<AGROW>
                continue;
            elseif ch == ':'
                out(end+1) = ": "; %#ok<AGROW>
                continue;
            end
        end
        out(end+1) = string(ch); %#ok<AGROW>
        esc = (~esc && ch == '\\');
        if ch ~= '\\'
            esc = false;
        end
    end
    s = char(join(out, ""));
end
