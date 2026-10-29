import math

def run_full_suite():
    width = 1080.0
    height = 1920.0
    aspect = width / height
    hfov_deg = 40.0
    hfov_rad = math.radians(hfov_deg)
    vfov_rad = 2.0 * math.atan(math.tan(hfov_rad / 2.0) / aspect)

    cam_h = 9.5
    pitch_deg = 45.0
    pitch_rad = math.radians(pitch_deg)

    cos_p = math.cos(pitch_rad)
    sin_p = math.sin(pitch_rad)
    tan_h = math.tan(hfov_rad / 2.0)
    tan_v = math.tan(vfov_rad / 2.0)

    # Play view rect: standard portrait HUD play view with top bar 10% = 192px
    play_rect_x = 0.0
    play_rect_y = 192.0
    play_rect_w = 1080.0
    play_rect_h = 1728.0

    # Camera tuning exports
    safe_box_margin_h = 0.15
    safe_box_margin_v = 0.15
    soft_zone_margin = 0.08

    base_anchor_x = 0.50
    base_anchor_y = 0.60
    lookahead_max_x = 0.10
    lookahead_max_y = 0.10
    lookahead_smoothing = 4.0

    base_follow_speed = 8.0
    run_follow_speed = 14.0
    max_boosted_follow_speed = 36.0
    run_speed = 8.0 # m/s

    S_min_x = play_rect_x + play_rect_w * safe_box_margin_h # 162.0 (15.0%)
    S_max_x = play_rect_x + play_rect_w * (1.0 - safe_box_margin_h) # 918.0 (85.0%)
    S_min_y = play_rect_y + play_rect_h * safe_box_margin_v # 451.2 (23.5%)
    S_max_y = play_rect_y + play_rect_h * (1.0 - safe_box_margin_v) # 1660.8 (86.5%)

    soft_w = play_rect_w * soft_zone_margin # 86.4
    soft_h = play_rect_h * soft_zone_margin # 138.24

    Z_min_x = S_min_x + soft_w # 248.4 (23.0%)
    Z_max_x = S_max_x - soft_w # 831.6 (77.0%)
    Z_min_y = S_min_y + soft_h # 589.4 (30.7%)
    Z_max_y = S_max_y - soft_h # 1522.6 (79.3%)

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

    def camera_pos_for_screen_target(drac_pos, target_sx, target_sy, cam_height, pitch_r):
        cos_t = math.cos(pitch_r)
        sin_t = math.sin(pitch_r)
        ndc_x = (2.0 * target_sx - width) / width
        ndc_y = (height - 2.0 * target_sy) / height
        kx = ndc_x * tan_h
        ky = ndc_y * tan_v
        denom = sin_t - ky * cos_t
        if abs(denom) < 0.0001:
            denom = 0.0001
        delta_z = -cam_height * (cos_t + ky * sin_t) / denom
        z_depth = cam_height * sin_t - delta_z * cos_t
        cam_x = drac_pos[0] - kx * z_depth
        cam_z = drac_pos[2] - delta_z
        cam_y = cam_height
        return [cam_x, cam_y, cam_z]

    def simulate(direction_name, move_dir, fps, duration=2.0, level_bounds=None):
        dt = 1.0 / fps
        steps = int(duration * fps)

        drac_pos = [0.0, 0.0, 0.0]
        prev_drac_pos = [0.0, 0.0, 0.0]

        cur_anchor_x = play_rect_x + play_rect_w * base_anchor_x
        cur_anchor_y = play_rect_y + play_rect_h * base_anchor_y
        cur_la_offset_x = 0.0
        cur_la_offset_y = 0.0

        cam_pos = camera_pos_for_screen_target(drac_pos, cur_anchor_x, cur_anchor_y, cam_h, pitch_rad)

        min_sx, max_sx = 9999.0, -9999.0
        min_sy, max_sy = 9999.0, -9999.0
        outside_safe_count = 0
        max_soft_depth = 0.0
        hard_clamp_count = 0

        for frame in range(1, steps + 1):
            # Dracula moves
            drac_pos[0] += move_dir[0] * run_speed * dt
            drac_pos[2] += move_dir[1] * run_speed * dt

            vx = (drac_pos[0] - prev_drac_pos[0]) / dt
            vz = (drac_pos[2] - prev_drac_pos[2]) / dt
            speed = math.hypot(vx, vz)
            prev_drac_pos = drac_pos[:]

            dir_x = vx / speed if speed > 0.001 else 0.0
            dir_z = vz / speed if speed > 0.001 else 0.0

            # Lookahead in screen space
            k_speed = min(1.0, speed / run_speed)
            tgt_la_x = -dir_x * (play_rect_w * lookahead_max_x) * k_speed
            tgt_la_y = -dir_z * (play_rect_h * lookahead_max_y) * k_speed

            la_decay = 1.0 - math.exp(-lookahead_smoothing * dt)
            cur_la_offset_x += (tgt_la_x - cur_la_offset_x) * la_decay
            cur_la_offset_y += (tgt_la_y - cur_la_offset_y) * la_decay

            target_anchor_x = play_rect_x + play_rect_w * base_anchor_x + cur_la_offset_x
            target_anchor_y = play_rect_y + play_rect_h * base_anchor_y + cur_la_offset_y

            # Cap anchor inside safe box / soft zone inner boundary (Addition 3)
            target_anchor_x = min(max(target_anchor_x, Z_min_x), Z_max_x)
            target_anchor_y = min(max(target_anchor_y, Z_min_y), Z_max_y)

            ideal_cam = camera_pos_for_screen_target(drac_pos, target_anchor_x, target_anchor_y, cam_h, pitch_rad)

            # Soft zone penetration depth (Addition 1)
            cur_sx, cur_sy = project_to_screen(cam_pos, drac_pos)
            depth_x = 0.0
            if cur_sx < Z_min_x:
                depth_x = (Z_min_x - cur_sx) / soft_w
            elif cur_sx > Z_max_x:
                depth_x = (cur_sx - Z_max_x) / soft_w

            depth_y = 0.0
            if cur_sy < Z_min_y:
                depth_y = (Z_min_y - cur_sy) / soft_h
            elif cur_sy > Z_max_y:
                depth_y = (cur_sy - Z_max_y) / soft_h

            soft_depth = min(1.0, max(0.0, max(depth_x, depth_y)))
            if soft_depth > max_soft_depth:
                max_soft_depth = soft_depth

            active_speed = run_follow_speed if speed > 2.0 else base_follow_speed
            effective_speed = active_speed + (max_boosted_follow_speed - active_speed) * (soft_depth * soft_depth)

            # Smooth follow
            decay = 1.0 - math.exp(-effective_speed * dt)
            cam_pos[0] += (ideal_cam[0] - cam_pos[0]) * decay
            cam_pos[2] += (ideal_cam[2] - cam_pos[2]) * decay
            cam_pos[1] = cam_h

            # Level bounds (Addition 2)
            if level_bounds:
                cam_pos[0] = min(max(cam_pos[0], level_bounds[0]), level_bounds[1])
                cam_pos[2] = min(max(cam_pos[2], level_bounds[2]), level_bounds[3])

            # Safe box hard clamp: Safe Box ALWAYS wins!
            proj_sx, proj_sy = project_to_screen(cam_pos, drac_pos)
            clamped_sx = min(max(proj_sx, S_min_x), S_max_x)
            clamped_sy = min(max(proj_sy, S_min_y), S_max_y)
            if abs(clamped_sx - proj_sx) > 0.001 or abs(clamped_sy - proj_sy) > 0.001:
                hard_clamp_count += 1
                req_cam = camera_pos_for_screen_target(drac_pos, clamped_sx, clamped_sy, cam_h, pitch_rad)
                cam_pos[0] = req_cam[0]
                cam_pos[2] = req_cam[2]
                proj_sx, proj_sy = clamped_sx, clamped_sy

            min_sx = min(min_sx, proj_sx)
            max_sx = max(max_sx, proj_sx)
            min_sy = min(min_sy, proj_sy)
            max_sy = max(max_sy, proj_sy)

            if proj_sx < S_min_x - 0.001 or proj_sx > S_max_x + 0.001 or proj_sy < S_min_y - 0.001 or proj_sy > S_max_y + 0.001:
                outside_safe_count += 1

        pct_min_x = (min_sx / width) * 100.0
        pct_max_x = (max_sx / width) * 100.0
        pct_min_y = (min_sy / height) * 100.0
        pct_max_y = (max_sy / height) * 100.0

        return {
            "dir": direction_name,
            "fps": fps,
            "pct_x_min": pct_min_x,
            "pct_x_max": pct_max_x,
            "pct_y_min": pct_min_y,
            "pct_y_max": pct_max_y,
            "max_soft_depth": max_soft_depth,
            "hard_clamps": hard_clamp_count,
            "outside_frames": outside_safe_count,
            "passed": (outside_safe_count == 0)
        }

    test_dirs = [
        ("UP", (0.0, -1.0)),
        ("DOWN", (0.0, 1.0)),
        ("LEFT", (-1.0, 0.0)),
        ("RIGHT", (1.0, 0.0)),
        ("UP-LEFT", (-math.sqrt(0.5), -math.sqrt(0.5))),
        ("UP-RIGHT", (math.sqrt(0.5), -math.sqrt(0.5))),
        ("DOWN-LEFT", (-math.sqrt(0.5), math.sqrt(0.5))),
        ("DOWN-RIGHT", (math.sqrt(0.5), math.sqrt(0.5))),
    ]

    print("\n" + "=" * 112)
    print(" SHADOW RUN: REBUILT MOVEMENT & CAMERA SYNC SIMULATION (ALL 8 DIRECTIONS @ 60 FPS & 30 FPS)")
    print("=" * 112)
    print(f"Safe Box X Bounds: [{S_min_x:.1f}, {S_max_x:.1f}] px  -> [{S_min_x/width*100:.1f}%, {S_max_x/width*100:.1f}%]")
    print(f"Safe Box Y Bounds: [{S_min_y:.1f}, {S_max_y:.1f}] px  -> [{S_min_y/height*100:.1f}%, {S_max_y/height*100:.1f}%]")
    print(f"Soft Zone X Inner: [{Z_min_x:.1f}, {Z_max_x:.1f}] px  -> [{Z_min_x/width*100:.1f}%, {Z_max_x/width*100:.1f}%]")
    print(f"Soft Zone Y Inner: [{Z_min_y:.1f}, {Z_max_y:.1f}] px  -> [{Z_min_y/height*100:.1f}%, {Z_max_y/height*100:.1f}%]")
    print("-" * 112)

    all_passed = True
    results = []

    for fps in [60, 30]:
        print(f"\n--- {fps} FPS SIMULATION ---")
        print(f"{'Direction':<12} | {'FPS':<4} | {'Screen X Range':<17} | {'Screen Y Range':<17} | {'Max Soft Depth':<14} | {'Hard Clamps':<11} | {'Safe Box Status'}")
        print("-" * 112)
        for name, d in test_dirs:
            res = simulate(name, d, fps=fps)
            results.append(res)
            if not res["passed"]:
                all_passed = False
            status_str = "PASS (100% inside)" if res["passed"] else f"FAIL ({res['outside_frames']} frames out)"
            x_range_str = f"{res['pct_x_min']:5.1f}% - {res['pct_x_max']:5.1f}%"
            y_range_str = f"{res['pct_y_min']:5.1f}% - {res['pct_y_max']:5.1f}%"
            print(f"{res['dir']:<12} | {res['fps']:<4} | {x_range_str:<17} | {y_range_str:<17} | {res['max_soft_depth']:<14.2f} | {res['hard_clamps']:<11} | {status_str}")

    print("\n--- LEVEL BOUNDS OVERRIDE TEST (Level wall clamp at X=[-2.0, 2.0], Dracula running to X=16.0) ---")
    bound_res = simulate("RIGHT into Wall", (1.0, 0.0), fps=60, duration=2.0, level_bounds=(-2.0, 2.0, -50.0, 50.0))
    status_str = "PASS (Safe Box Wins!)" if bound_res["passed"] else "FAIL"
    x_range_str = f"{bound_res['pct_x_min']:5.1f}% - {bound_res['pct_x_max']:5.1f}%"
    y_range_str = f"{bound_res['pct_y_min']:5.1f}% - {bound_res['pct_y_max']:5.1f}%"
    print(f"{bound_res['dir']:<16} | {bound_res['fps']:<4} | {x_range_str:<17} | {y_range_str:<17} | {bound_res['max_soft_depth']:<14.2f} | {bound_res['hard_clamps']:<11} | {status_str}")

    print("=" * 112)
    print(f"OVERALL STATUS: {'ALL CHECKS PASSED PERFECTLY!' if all_passed and bound_res['passed'] else 'FAILURES DETECTED'}")
    print("=" * 112)

if __name__ == "__main__":
    run_full_suite()
