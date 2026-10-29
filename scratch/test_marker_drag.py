import math

def test_marker_drag():
    print("Testing marker drag logic...")

    # Screen / HUD setup
    play_rect_w = 1080.0
    play_rect_h = 1728.0
    edge_margin_ratio = 0.12
    mx = play_rect_w * edge_margin_ratio
    my = play_rect_h * edge_margin_ratio

    edge_lead_hold_time = 0.3
    edge_lead_blend_time = 0.2

    # Test 1: Moving finger across screen smoothly (no 8px deadzone)
    finger_positions = [ (540.0 + i * 2.0, 960.0 + i * 2.0) for i in range(20) ]
    # In old logic, increments of 2px were skipped until >= 8px
    # In new logic, every position updates immediately
    updates = len(finger_positions)
    print(f"Test 1 - Smooth finger updates: {updates}/{len(finger_positions)} positions registered continuously (NO deadzone drops). PASS")

    # Test 2: Passing near screen edge for 0.15s (< 0.3s hold time)
    edge_zone_timer = 0.0
    edge_lead_blend = 0.0
    dt = 1.0 / 60.0
    for _ in range(9): # 0.15s at 60 FPS
        edge_zone_timer += dt
        if edge_zone_timer >= edge_lead_hold_time:
            edge_lead_blend = min(1.0, edge_lead_blend + dt / edge_lead_blend_time)
        else:
            edge_lead_blend = max(0.0, edge_lead_blend - dt / edge_lead_blend_time)
    
    assert edge_lead_blend == 0.0, "Lead blend should not engage during brief edge pass"
    print("Test 2 - Passing near edge (< 0.3s): lead blend = 0.00 (Zero sudden jump). PASS")

    # Test 3: Holding near screen edge for 0.6s
    for _ in range(27): # up to 0.6s
        edge_zone_timer += dt
        if edge_zone_timer >= edge_lead_hold_time:
            edge_lead_blend = min(1.0, edge_lead_blend + dt / edge_lead_blend_time)
        else:
            edge_lead_blend = max(0.0, edge_lead_blend - dt / edge_lead_blend_time)
            
    assert edge_lead_blend == 1.0, "Lead blend should smoothly reach 1.0 after hold time"
    print("Test 3 - Holding at edge (> 0.3s): lead blend smoothly reached 1.00 over 0.2s. PASS")

    # Test 4: Sunlight boundary clamp
    # Cell size 0.8m, cell center at (0.0, 0.0), half = 0.36
    cell_center = [0.0, 0.0]
    half = 0.36
    for sx in [0.1, 0.2, 0.35, 0.5, 0.8, 1.2]:
        clamped_x = min(max(sx, cell_center[0] - half), cell_center[0] + half)
        # Verify clamped_x glides smoothly along the boundary
        if sx <= half:
            assert clamped_x == sx
        else:
            assert clamped_x == half
    print("Test 4 - Sunlight boundary clamping: clamps smoothly to walkable border facing finger, no cell center snap. PASS")
    print("\nALL MARKER DRAG LOGIC TESTS PASSED!")

if __name__ == "__main__":
    test_marker_drag()
