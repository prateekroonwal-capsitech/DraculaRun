import math

# Camera & viewport setup
width = 1080
height = 1920
aspect = width / height # 0.5625
hfov_deg = 40.0 # KEEP_WIDTH
vfov_rad = 2.0 * math.atan(math.tan(math.radians(hfov_deg / 2.0)) / aspect)
vfov_deg = math.degrees(vfov_rad)

cam_height = 9.5
cam_distance = 5.2
pitch_deg = 45.0
pitch_rad = math.radians(pitch_deg)

lateral_follow = 0.35
f_smooth = 18.0
l_smooth = 11.0
lookahead_distance = 2.5
lookahead_smoothing = 3.5
follow_dead_zone = 0.04
run_speed = 8.0
center_x = 0.0

def project_to_screen(cam_pos, point_3d):
    # Vector from camera to point in world space
    rel = (point_3d[0] - cam_pos[0], point_3d[1] - cam_pos[1], point_3d[2] - cam_pos[2])
    # Camera rotation is -pitch around X axis
    # In camera view space:
    # forward is -Z, right is +X, up is +Y
    cos_p = math.cos(pitch_rad)
    sin_p = math.sin(pitch_rad)
    
    # World to View: rotate by +pitch around X
    vx = rel[0]
    vy = rel[1] * cos_p - rel[2] * sin_p
    vz = rel[1] * sin_p + rel[2] * cos_p
    
    # In Godot camera space: looking along -Z
    # z_depth is -vz
    z_depth = -vz
    if z_depth <= 0.001:
        return None, None
        
    tan_half_v = math.tan(vfov_rad / 2.0)
    tan_half_h = math.tan(math.radians(hfov_deg / 2.0))
    
    ndc_x = (vx / z_depth) / tan_half_h
    ndc_y = (vy / z_depth) / tan_half_v
    
    # Screen coordinates: (0,0) top-left, (1080, 1920) bottom-right
    screen_x = (ndc_x + 1.0) * 0.5 * width
    screen_y = (1.0 - ndc_y) * 0.5 * height
    return screen_x, screen_y

def simulate_run(direction_name, move_dir, duration=1.0, fps=60):
    dt = 1.0 / fps
    steps = int(duration * fps)
    
    drac_pos = [0.0, 0.0, 0.0]
    prev_drac_pos = [0.0, 0.0, 0.0]
    focus_pos = [0.0, 0.0, 0.0]
    cur_la_x = 0.0
    cur_la_z = 0.0
    
    print(f"\n=======================================================")
    print(f" SIMULATION: RUNNING {direction_name} (dir={move_dir})")
    print(f"=======================================================")
    print(f"Frame | Dracula World (X, Z) | Camera Pos (X, Y, Z) | Lookahead (X, Z) | Screen (X, Y) | Screen % Y")
    print("-" * 90)
    
    for frame in range(steps + 1):
        # Update Dracula
        if frame > 0:
            drac_pos[0] += move_dir[0] * run_speed * dt
            drac_pos[2] += move_dir[1] * run_speed * dt
            
        # Camera update logic from RunCameraController.gd
        tp = drac_pos[:]
        delta_pos = (tp[0] - prev_drac_pos[0], tp[1] - prev_drac_pos[1], tp[2] - prev_drac_pos[2])
        d2 = (delta_pos[0], delta_pos[2])
        d_speed = math.hypot(d2[0], d2[1]) / dt if frame > 0 else 0.0
        
        move_vec = (0.0, 0.0)
        if d_speed > 0.15:
            move_vec = (d2[0] / (d_speed * dt), d2[1] / (d_speed * dt))
            
        prev_drac_pos = drac_pos[:]
        
        target_la_x = 0.0
        target_la_z = 0.0
        if d_speed > 0.2 and move_vec != (0.0, 0.0):
            target_la_x = move_vec[0] * lookahead_distance
            target_la_z = move_vec[1] * lookahead_distance
            
        la_decay = 1.0 - math.exp(-lookahead_smoothing * dt)
        cur_la_x += (target_la_x - cur_la_x) * la_decay
        cur_la_z += (target_la_z - cur_la_z) * la_decay
        
        target_z = tp[2] + cur_la_z
        target_x = center_x + (tp[0] - center_x) * lateral_follow + (cur_la_x * lateral_follow)
        
        if abs(target_z - focus_pos[2]) > follow_dead_zone:
            tz_decay = 1.0 - math.exp(-f_smooth * dt)
            focus_pos[2] += (target_z - focus_pos[2]) * tz_decay
            
        if abs(target_x - focus_pos[0]) > follow_dead_zone:
            tx_decay = 1.0 - math.exp(-l_smooth * dt)
            focus_pos[0] += (target_x - focus_pos[0]) * tx_decay
            
        cam_pos = (focus_pos[0], cam_height, focus_pos[2] + cam_distance)
        
        sx, sy = project_to_screen(cam_pos, drac_pos)
        sy_pct = (sy / height) * 100.0 if sy is not None else -999.0
        
        if frame in [0, 5, 10, 15, 20, 30, 45, 60]:
            off_screen = " !!! OFF SCREEN (TOP) !!!" if sy < 0 else (" !!! OFF SCREEN (BOTTOM) !!!" if sy > height else "")
            print(f"{frame:5d} | ({drac_pos[0]:6.2f}, {drac_pos[2]:6.2f}) | ({cam_pos[0]:5.2f}, {cam_pos[1]:4.1f}, {cam_pos[2]:6.2f}) | ({cur_la_x:5.2f}, {cur_la_z:5.2f}) | ({sx:6.1f}, {sy:6.1f}) | {sy_pct:5.1f}%{off_screen}")

simulate_run("UP (Screen Top / -Z)", (0.0, -1.0))
simulate_run("DOWN (Screen Bottom / +Z)", (0.0, 1.0))
simulate_run("LEFT (Screen Left / -X)", (-1.0, 0.0))
simulate_run("RIGHT (Screen Right / +X)", (1.0, 0.0))
