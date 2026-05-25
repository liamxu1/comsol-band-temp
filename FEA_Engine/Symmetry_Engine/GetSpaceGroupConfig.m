function [sg_name, phi_degrees, n_ops, orbit_func] = GetSpaceGroupConfig(sg_input)
    % GetSpaceGroupConfig: 17种二维空间群(Wallpaper Groups)几何与对称性配置路由
    
    % --- 1. IUCr 标准 17 种二维空间群字典 ---
    standard_names = {'p1', 'p2', 'pm', 'pg', 'cm', 'p2mm', 'p2mg', ...
                      'p2gg', 'c2mm', 'p4', 'p4mm', 'p4gm', 'p3', ...
                      'p3m1', 'p31m', 'p6', 'p6mm'};
    
    % --- 2. 解析输入 ---
    if isnumeric(sg_input)
        if sg_input >= 1 && sg_input <= 17
            sg_name = standard_names{sg_input};
        else
            error('空间群序号必须在 1 到 17 之间！当前输入: %d', sg_input);
        end
    elseif ischar(sg_input) || isstring(sg_input)
        sg_name = lower(char(sg_input));
    else
        error('输入类型错误：必须是 1-17 的整数或空间群名称字符串。');
    end

    % --- 3. 核心路由分配 ---
    switch sg_name
        case 'p1'    % 1
            phi_degrees = 90; n_ops = 1; orbit_func = @Orbits_p1;
        case 'p2'    % 2
            phi_degrees = 90; n_ops = 2; orbit_func = @Orbits_p2;
        case 'pm'    % 3
            phi_degrees = 90; n_ops = 2; orbit_func = @Orbits_pm;
        case 'pg'    % 4
            phi_degrees = 90; n_ops = 2; orbit_func = @Orbits_pg;
        case 'cm'    % 5
            phi_degrees = 90; n_ops = 4; orbit_func = @Orbits_cm;
        case 'p2mm'  % 6
            phi_degrees = 90; n_ops = 4; orbit_func = @Orbits_p2mm;
        case 'p2mg'  % 7
            phi_degrees = 90; n_ops = 4; orbit_func = @Orbits_p2mg;
        case 'p2gg'  % 8
            phi_degrees = 90; n_ops = 4; orbit_func = @Orbits_p2gg;
        case 'c2mm'  % 9
            phi_degrees = 90; n_ops = 8; orbit_func = @Orbits_c2mm;
        case 'p4'    % 10
            phi_degrees = 90; n_ops = 4; orbit_func = @Orbits_p4;
        case 'p4mm'  % 11
            phi_degrees = 90; n_ops = 8; orbit_func = @Orbits_p4mm;
        case 'p4gm'  % 12
            phi_degrees = 90; n_ops = 8; orbit_func = @Orbits_p4gm;
        case 'p3'    % 13
            phi_degrees = 120; n_ops = 3; orbit_func = @Orbits_p3;
        case 'p3m1'  % 14
            phi_degrees = 120; n_ops = 6; orbit_func = @Orbits_p3m1;
        case 'p31m'  % 15
            phi_degrees = 120; n_ops = 6; orbit_func = @Orbits_p31m;
        case 'p6'    % 16
            phi_degrees = 120; n_ops = 6; orbit_func = @Orbits_p6;
        case 'p6mm'  % 17
            phi_degrees = 120; n_ops = 12; orbit_func = @Orbits_p6mm;
        otherwise
            error('空间群 "%s" 的配置出现异常！', sg_name);
    end
end

%% =========================================================================
%  以下为 17 种平面群的局部算子函数 (Local Functions)
%  统一执行取模与边界保护
% =========================================================================

function [u_out, v_out] = apply_mod(u_list, v_list)
    u_out = mod(u_list, 1.0);
    v_out = mod(v_list, 1.0);
    u_out(u_out < 0) = u_out(u_out < 0) + 1;
    v_out(v_out < 0) = v_out(v_out < 0) + 1;
end

% 1. p1
function [u, v] = Orbits_p1(u0, v0)
    u_list = [u0];
    v_list = [v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 2. p2
function [u, v] = Orbits_p2(u0, v0)
    u_list = [u0; -u0];
    v_list = [v0; -v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 3. pm
function [u, v] = Orbits_pm(u0, v0)
    u_list = [u0; -u0];
    v_list = [v0;  v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 4. pg
function [u, v] = Orbits_pg(u0, v0)
    u_list = [u0; -u0];
    v_list = [v0; v0 + 0.5];
    [u, v] = apply_mod(u_list, v_list);
end

% 5. cm
function [u, v] = Orbits_cm(u0, v0)
    u_list = [u0; -u0; u0 + 0.5; -u0 + 0.5];
    v_list = [v0;  v0; v0 + 0.5;  v0 + 0.5];
    [u, v] = apply_mod(u_list, v_list);
end

% 6. p2mm
function [u, v] = Orbits_p2mm(u0, v0)
    u_list = [u0; -u0; -u0;  u0];
    v_list = [v0; -v0;  v0; -v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 7. p2mg
function [u, v] = Orbits_p2mg(u0, v0)
    u_list = [u0; -u0; -u0 + 0.5; u0 + 0.5];
    v_list = [v0; -v0;  v0;      -v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 8. p2gg
function [u, v] = Orbits_p2gg(u0, v0)
    u_list = [u0; -u0; -u0 + 0.5;  u0 + 0.5];
    v_list = [v0; -v0;  v0 + 0.5; -v0 + 0.5];
    [u, v] = apply_mod(u_list, v_list);
end

% 9. c2mm
function [u, v] = Orbits_c2mm(u0, v0)
    u_list = [u0; -u0; -u0; u0; u0+0.5; -u0+0.5; -u0+0.5; u0+0.5];
    v_list = [v0; -v0; v0; -v0; v0+0.5; -v0+0.5; v0+0.5; -v0+0.5];
    [u, v] = apply_mod(u_list, v_list);
end

% 10. p4
function [u, v] = Orbits_p4(u0, v0)
    u_list = [u0; -u0; -v0;  v0];
    v_list = [v0; -v0;  u0; -u0];
    [u, v] = apply_mod(u_list, v_list);
end

% 11. p4mm
function [u, v] = Orbits_p4mm(u0, v0)
    u_list = [u0; -u0; -v0;  v0; -u0;  u0;  v0; -v0];
    v_list = [v0; -v0;  u0; -u0;  v0; -v0;  u0; -u0];
    [u, v] = apply_mod(u_list, v_list);
end

% 12. p4gm
function [u, v] = Orbits_p4gm(u0, v0)
    u_list = [u0; -u0; -v0; v0; -u0+0.5; u0+0.5; v0+0.5; -v0+0.5];
    v_list = [v0; -v0; u0; -u0; v0+0.5; -v0+0.5; u0+0.5; -u0+0.5];
    [u, v] = apply_mod(u_list, v_list);
end

% 13. p3
function [u, v] = Orbits_p3(u0, v0)
    u_list = [u0; -v0; -u0 + v0];
    v_list = [v0; u0 - v0; -u0];
    [u, v] = apply_mod(u_list, v_list);
end

% 14. p3m1
function [u, v] = Orbits_p3m1(u0, v0)
    u_list = [u0; -v0; -u0+v0; -v0; -u0+v0; u0];
    v_list = [v0; u0-v0; -u0; -u0; v0; u0-v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 15. p31m
function [u, v] = Orbits_p31m(u0, v0)
    u_list = [u0; -v0; -u0+v0; v0; u0-v0; -u0];
    v_list = [v0; u0-v0; -u0; u0; -v0; -u0+v0];
    [u, v] = apply_mod(u_list, v_list);
end

% 16. p6
function [u, v] = Orbits_p6(u0, v0)
    u_list = [u0; -v0; -u0+v0; -u0; v0; u0-v0];
    v_list = [v0; u0-v0; -u0; -v0; -u0+v0; u0];
    [u, v] = apply_mod(u_list, v_list);
end

% 17. p6mm
function [u, v] = Orbits_p6mm(u0, v0)
    u_list = [u0; -v0; -u0+v0; -u0; v0; u0-v0; -v0; -u0+v0; u0; v0; u0-v0; -u0];
    v_list = [v0; u0-v0; -u0; -v0; -u0+v0; u0; -u0; v0; u0-v0; u0; -v0; -u0+v0];
    [u, v] = apply_mod(u_list, v_list);
end