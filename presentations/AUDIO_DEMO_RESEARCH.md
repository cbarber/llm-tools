# Audio Demo Research for Live Schmitt Trigger Visualization

## Goal

Demonstrate Schmitt trigger / noise tolerance concept with live audio:
- Feed audio from meeting room computer
- Show waveform visualization in terminal
- Convert to square wave
- Illustrate how noise affects signal
- Map to: clean = success, noisy = compounding errors

## Technical Requirements

### 1. Audio Input
- Capture audio from meeting room system
- Or: Use microphone input (music playing, or speak into mic)
- Real-time processing (low latency)
- Terminal-based (no GUI)

### 2. Visualization
- Waveform display in terminal
- Real-time updates
- Clear enough to project in meeting room
- ASCII/Unicode art or terminal graphics protocol

### 3. Square Wave Conversion
- Schmitt trigger algorithm
- Configurable thresholds (upper/lower hysteresis)
- Visual comparison: with hysteresis vs without

## Terminal Audio Tools Research

### Option 1: CAVA (Console-based Audio Visualizer)
**What it is:** Real-time audio visualizer for terminal

**Pros:**
- Designed for terminals
- Real-time visualization
- Multiple visualization modes
- Available in nixpkgs

**Cons:**
- Primarily bar graph (frequency spectrum)
- Not designed for square wave conversion demo
- Would need custom mode/scripting

**Installation:**
```bash
nix-shell -p cava
```

**Usage:**
```bash
cava
```

**Verdict:** Good for audio viz, but doesn't directly show Schmitt trigger concept.

---

### Option 2: sox (Sound eXchange) + Custom Script
**What it is:** Audio processing swiss army knife

**Pros:**
- Can generate test signals
- Can apply effects (including clipping for square wave)
- Scriptable
- Available in nixpkgs

**Cons:**
- Not a visualizer (need separate tool)
- Complex scripting required
- Not real-time interactive

**Installation:**
```bash
nix-shell -p sox
```

**Usage:**
```bash
# Generate sine wave
sox -n sine.wav synth 3 sine 440

# Convert to square wave (hard clipping)
sox sine.wav square.wav overdrive 20

# Play
play square.wav
```

**Verdict:** Good for audio generation, but visualization separate concern.

---

### Option 3: gnuplot + arecord/sox Pipeline
**What it is:** Data plotting with audio input pipeline

**Pros:**
- Can plot waveforms
- Real-time plotting possible with `dumb` terminal
- Available in nixpkgs

**Cons:**
- Complex pipeline setup
- gnuplot dumb terminal is low resolution
- Not optimized for live demos
- Easy to break

**Installation:**
```bash
nix-shell -p gnuplot sox alsa-utils
```

**Usage:**
```bash
# Record audio and pipe to gnuplot
arecord -f S16_LE -r 44100 -c 1 -d 5 | \
  sox -t raw -r 44100 -c 1 -b 16 -e signed-integer - -t dat - | \
  gnuplot -e "set term dumb; plot '-' with lines"
```

**Verdict:** Possible but fragile, high complexity.

---

### Option 4: ttyplot + Custom Audio Sampler
**What it is:** Real-time plotting for terminal

**Pros:**
- Designed for real-time data
- Clean ASCII art plots
- Can pipe data from any source

**Cons:**
- Need custom script to sample audio
- May not handle audio sampling rates well
- Not specifically for audio

**Installation:**
```bash
# Not in nixpkgs, need to package or build
git clone https://github.com/tenox7/ttyplot
cd ttyplot
make
```

**Verdict:** Interesting but requires packaging work.

---

### Option 5: Pre-recorded Visualization (Recommended)
**What it is:** Create animation beforehand, play in terminal

**Pros:**
- No technical risk during presentation
- Can perfect the visualization
- Reliable, repeatable
- Can use any tool to create

**Cons:**
- Not "live" (but is it necessary?)
- Less impressive than live audio

**Approaches:**

#### A. Asciinema Recording
Record a session showing:
1. Audio waveform (clean signal)
2. Audio waveform (noisy signal)
3. Square wave conversion (no hysteresis) - jittery
4. Square wave conversion (with hysteresis) - stable

```bash
asciinema rec audio-demo.cast
# Run your visualization
asciinema play audio-demo.cast
```

#### B. Animated ASCII Art
Use tool like `jp2a` or custom script to create frame-by-frame animation:
```bash
# Convert images to ASCII frames
for i in frame*.png; do
  jp2a --width=80 $i > ${i%.png}.txt
done

# Play frames
for i in frame*.txt; do
  clear
  cat $i
  sleep 0.1
done
```

#### C. Static Diagram with Annotations
Create clear diagram in markdown/ASCII:
```
Clean Signal (Success State)
━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ╱╲    ╱╲    ╱╲    ╱╲
 ╱  ╲  ╱  ╲  ╱  ╲  ╱  ╲
╱    ╲╱    ╲╱    ╲╱    ╲
━━━━━━━━━━━━━━━━━━━━━━━━━━━

↓ Square Wave Conversion

With Hysteresis (Guardrails)
━━━━━━━━━━━━━━━━━━━━━━━━━━━
████████      ████████      
        ██████        ██████
━━━━━━━━━━━━━━━━━━━━━━━━━━━
     STABLE SUCCESS


Noisy Signal (Compounding Errors)
━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ╱╲ ╱╲ ╱╲   ╱╲    ╱╲╱╲
 ╱  ╲ ╲╱ ╲  ╱ ╲   ╱   ╲
╱    ╲    ╲╱   ╲ ╱     ╲
━━━━━━━━━━━━━━━━━━━━━━━━━━━

↓ Square Wave Conversion

Without Hysteresis (No Guardrails)
━━━━━━━━━━━━━━━━━━━━━━━━━━━
██ ██ ██   ███   ██ ██
  █  █  ███   ███  █  ██
━━━━━━━━━━━━━━━━━━━━━━━━━━━
    JITTERY FAILURE
```

**Verdict:** Most reliable, can perfect beforehand, zero technical risk.

---

## Recommendation: Hybrid Approach

### Primary: Pre-recorded Visualization
Create a polished, pre-recorded demonstration that:
1. Shows concept clearly
2. Has zero risk of failure
3. Can be perfected beforehand
4. Plays in terminal (asciinema or script)

### Bonus: Live Audio (Time Permitting)
If you have time and can test thoroughly:
- Set up CAVA for live audio visualization
- Show audience "here's what live audio looks like"
- Then switch to pre-recorded for Schmitt trigger detail

### Why Hybrid?
- **Primary is reliable** (won't fail during talk)
- **Bonus adds wow factor** (if it works)
- **Failure mode is graceful** (just skip to primary)
- **No content lost** (primary covers all concepts)

## Implementation Plan

### Phase 1: Create Static Diagram (Minimum Viable)
- [ ] Create ASCII art diagram showing:
  - Clean signal → stable square wave (with hysteresis)
  - Noisy signal → jittery square wave (without hysteresis)
- [ ] Embed in presentation markdown
- [ ] This is your fallback if nothing else works

**Time:** 30 minutes

**Risk:** Zero

**Impact:** Adequate (concept is clear)

---

### Phase 2: Pre-recorded Animation (Recommended)
- [ ] Use sox to generate test signals:
  ```bash
  # Clean sine wave
  sox -n clean.wav synth 3 sine 440
  
  # Noisy sine wave
  sox -n noisy.wav synth 3 sine 440 noise 0.3
  
  # Convert to square (hard clipping = no hysteresis)
  sox noisy.wav noisy_square.wav overdrive 20
  
  # Convert to square (gentle compression = hysteresis)
  sox noisy.wav noisy_square_smooth.wav compand 0.3,1 6:-70,-60,-20 -5 -90 0.2
  ```

- [ ] Create visualization script:
  ```bash
  #!/usr/bin/env bash
  # visualize-wave.sh
  
  echo "Clean Signal (Success State)"
  play -q clean.wav &
  sleep 1
  # Show waveform ASCII art
  
  echo "→ Square Wave (With Hysteresis)"
  # Show stable square wave
  sleep 2
  
  echo "Noisy Signal (Compounding Errors)"
  play -q noisy.wav &
  # Show noisy waveform
  
  echo "→ Square Wave (Without Hysteresis)"
  # Show jittery square wave
  ```

- [ ] Record with asciinema
- [ ] Test playback multiple times

**Time:** 2-3 hours

**Risk:** Low (pre-recorded, can retry)

**Impact:** High (clear, visual, memorable)

---

### Phase 3: Live Audio (Bonus, Optional)
- [ ] Test meeting room audio setup
  - Can you get audio input working?
  - What's the latency?
  - Does CAVA work reliably?

- [ ] Create live demo script:
  ```bash
  #!/usr/bin/env bash
  # live-audio-demo.sh
  
  echo "Starting live audio visualization..."
  echo "Play some music or speak into mic"
  cava
  ```

- [ ] Multiple dry runs in actual meeting room
- [ ] Have pre-recorded backup ready

**Time:** 4-5 hours (including testing)

**Risk:** Medium-High (live demo can fail)

**Impact:** High if works, but not worth it if risky

**Decision point:** Only do this if you have time and meeting room access for testing.

---

## Testing Checklist

### For Pre-recorded (Phase 2)
- [ ] Create audio files with sox
- [ ] Create visualization script
- [ ] Record with asciinema
- [ ] Test playback on different terminal sizes
- [ ] Test playback with presenterm integration
- [ ] Verify audio plays (if included in recording)
- [ ] Check timing (should be ~30-60 seconds total)

### For Live Demo (Phase 3)
- [ ] Test in meeting room with actual setup
- [ ] Verify audio input works
- [ ] Check CAVA or chosen visualizer works
- [ ] Test with projector (visibility)
- [ ] Dry run 3+ times
- [ ] Have killswitch to abort if failing
- [ ] Have pre-recorded backup loaded and ready

## Fallback Strategy

**If nothing works:**
1. Use static ASCII diagram (Phase 1)
2. Explain concept verbally with diagram
3. Emphasize the analogy, not the visualization

**The concept is more important than the demo.**

Don't let demo tech failure derail the presentation.

## Resources

### Nix Packages Needed
```bash
nix-shell -p sox cava alsa-utils
```

### Documentation
- sox: https://sox.sourceforge.net/
- CAVA: https://github.com/karlstav/cava
- asciinema: https://asciinema.org/

### Example Scripts
Location: `presentations/demo-scripts/` (to be created if pursuing Phase 2/3)

## Decision: What Should You Do?

**My recommendation:**

1. **Start with Phase 1** (static diagram) - 30 min investment, zero risk
2. **Only proceed to Phase 2** (pre-recorded) if you have 3+ hours and want the polish
3. **Skip Phase 3** (live audio) unless you have 5+ hours and meeting room access for testing

**Why?**
- Your content is strong without fancy demo
- Technical risk during presentation is high
- Time investment may not be worth the impact
- Static diagram communicates the concept adequately

**However:**
If you really want the visual impact and have the time, Phase 2 (pre-recorded) is achievable and lower risk than Phase 3.

**Questions to ask yourself:**
1. How much time do I really have?
2. Is the visual demo worth the time investment?
3. Am I comfortable with the technical risk?
4. Will this enhance or distract from my message?

Choose wisely. The presentation is already strong without it.
