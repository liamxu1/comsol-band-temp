function B_matrix = PrecomputeBasisMatrix_Unified(nelx, nely, coff_nx, coff_ny, deg_u, deg_v, orbit_func, n_ops)
    % 通用的 B 样条基矩阵预计算引擎 (矩阵形式)
    % 新增输入: orbit_func (算子函数句柄), n_ops (操作数)
    
    fprintf('>> Pre-computing Universal B-Spline Basis Matrix... ');
    
    est_nz = nelx * nely * (deg_u+1) * (deg_v+1) * n_ops; 
    rows = zeros(est_nz, 1);
    cols = zeros(est_nz, 1);
    vals = zeros(est_nz, 1);
    idx_counter = 0;
    
    M_basis = [ -1  3 -3  1;
                 3 -6  0  4;
                -3  3  3  1;
                 1  0  0  0 ] / 6.0;

    for i = 1:nelx
        for j = 1:nely
            pix_idx = (i-1)*nely + j;
            u0 = (i-0.5)/nelx; 
            v0 = (j-0.5)/nely;
            
            % 【核心修改】：通过传入的句柄动态调用轨道映射！
            [u_orb, v_orb] = orbit_func(u0, v0);
            
            for op = 1:length(u_orb)
                u_curr = u_orb(op);
                v_curr = v_orb(op);
                
                u_scaled = u_curr * coff_nx;
                v_scaled = v_curr * coff_ny;
                
                idx_u = min(floor(u_scaled), coff_nx - 1);
                idx_v = min(floor(v_scaled), coff_ny - 1);
                
                t_u = u_scaled - idx_u;
                t_v = v_scaled - idx_v;
                
                U_vec = [t_u^3; t_u^2; t_u; 1];
                V_vec = [t_v^3; t_v^2; t_v; 1];
                
                Nu_vals = M_basis * U_vec;
                Nv_vals = M_basis * V_vec;
                
                for k = 0:3 
                    for l = 0:3 
                        weight = Nu_vals(k+1) * Nv_vals(l+1) / n_ops; % 【核心修改】：使用传入的 n_ops
                        
                        raw_idx_u = idx_u - 3 + k; 
                        raw_idx_v = idx_v - 3 + l;
                        
                        real_cp_u = mod(raw_idx_u, coff_nx);
                        real_cp_v = mod(raw_idx_v, coff_ny);
                        
                        coeff_idx = (real_cp_v)*coff_nx + (real_cp_u+1);
                        
                        idx_counter = idx_counter + 1;
                        rows(idx_counter) = pix_idx;
                        cols(idx_counter) = coeff_idx;
                        vals(idx_counter) = weight;
                    end
                end
            end
        end
    end
    
    rows = rows(1:idx_counter);
    cols = cols(1:idx_counter);
    vals = vals(1:idx_counter);
    B_matrix = sparse(rows, cols, vals, nelx*nely, coff_nx*coff_ny);
    fprintf('Done.\n');
end