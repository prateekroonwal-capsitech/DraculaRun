import math

width = 1080.0
height = 1920.0
aspect = width / height
hfov_deg = 40.0
hfov_rad = math.radians(hfov_deg)
vfov_rad = 2.0 * math.atan(math.tan(hfov_rad / 2.0) / aspect)

H = 9.5
pitch_deg = 45.0
pitch_rad = math.radians(pitch_deg)

cos_p = math.cos(pitch_rad)
sin_p = math.sin(pitch_rad)
tan_h = math.tan(hfov_rad / 2.0)
tan_v = math.tan(vfov_rad / 2.0)

def project_to_screen(cam_pos, point_3d):
    rel = (point_3d[0] - cam_pos[0], point_3d[1] - cam_pos[1], point_3d[2] - cam_pos[2])
    vx = rel[0]
    vy = rel[1] * cos_p - rel[2] * sin_p
    vz = rel[1] * sin_p + rel[2] * cos_p
    z_depth = -vz
    if z_depth <= 0.001:
        return None, None
    ndc_x = (vx / z_depth) / tan_h
    ndc_y = (vy / z_depth) / tan_v
    sx = (ndc_x + 1.0) * 0.5 * width
    sy = (1.0 - ndc_y) * 0.5 * height
    return sx, sy

def camera_pos_for_screen_target(drac_pos, target_sx, target_sy, cam_h, pitch_r):
    cos_t = math.cos(pitch_r)
    sin_t = math.sin(pitch_r)
    
    ndc_x = (2.0 * target_sx - width) / width
    ndc_y = (height - 2.0 * target_sy) / height
    
    kx = ndc_x * tan_h
    ky = ndc_y * tan_v
    
    denom = sin_t - ky * cos_t
    if abs(denom) < 0.0001:
        denom = 0.0001
        
    delta_z = -cam_h * (cos_t + ky * sin_t) / denom
    z_depth = cam_h * sin_t - delta_z * cos_t
    
    cam_x = drac_pos[0] - kx * z_depth
    cam_z = drac_pos[2] - delta_z
    cam_y = cam_h
    return (cam_x, cam_y, cam_z)

# Test multiple target screen coordinates:
test_targets = [
    (540.0, 960.0),    # Exact center (50%, 50%)
    (540.0, 1152.0),   # 50% X, 60% Y
    (540.0, 1344.0),   # 50% X, 70% Y
    (324.0, 800.0),    # 30% X, ~42% Y
    (756.0, 1200.0),   # 70% X, ~62% Y
]

dracula = (3.5, 0.0, -12.0)

print("Verifying inverse camera placement formula:")
for sx, sy in test_targets:
    c_pos = camera_pos_for_screen_target(dracula, sx, sy, H, pitch_rad)
    proj_x, proj_y = project_to_screen(c_pos, dracula)
    err_x = abs(proj_x - sx)
    err_y = abs(proj_y - sy)
    print(f"Target: ({sx:6.1f}, {sy:6.1f}) -> Cam: ({c_pos[0]:6.2f}, {c_pos[1]:4.1f}, {c_pos[2]:6.2f}) -> Projected: ({proj_x:6.1f}, {proj_y:6.1f}) | Error: ({err_x:1.6f}, {err_y:1.6f}) px")
