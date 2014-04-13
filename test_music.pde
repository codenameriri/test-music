import themidibus.*;
import processing.serial.*;
import org.firmata.*;
import cc.arduino.*;

/*
*	Variables
*/

// Sketch properties
int WIDTH = 600;
int HEIGHT = 400;
boolean playing = false;

// Focus/Relax Level - Focus is positive (1 to 100), Relax is negative (-1 to -100)
int focusRelaxLevel = 0;
IntList levelHist = new IntList();
int MAX_FOCUS = 100;
int MAX_RELAX = -100;
int level = 0;

// BPM - Beats per minute, tempo, corresponds to pulse (average over X measures)
int pulse = 60;
IntList pulseHist = new IntList();
int bpm = pulse;

// Grain - "Frequency" of notes, 0 = 1/4 notes, 1 = 1/8 notes, 2 = 1/16 notes, 3 = 1/32 notes
// Corresponds to Focus/Relax Level (0 = 0 to 20, 1 = 20 to 50, 2 = 50 to 80, 3 = 80 to 100)
int grain = 0;
//IntList grainHist = new IntList();
float[] beats = {1, 0.5, 0.25, 0.125};

// Timekeeping
int phase = 1;
int PHASES_PER_SONG = 4;
int measure = 1;
int MEASURES_PER_PHASE = 8;
int beat = 0;
int BEATS_PER_MEASURE = 4;
int mils = millis();
int lastMils = mils;

// Music Stuff
int[] scale = {0, 2, 4, 7, 9};
int PITCH_C = 60;
int PITCH_F = 65;
int PITCH_G = 67;
int pitch = PITCH_C;

// MidiBus
MidiBus mb;
String MIDI_PORT_OUT = "Virtual MIDI Bus";
int channel1 = 0;
int channel2 = 1;
int channel3 = 2;
int channel4 = 3;
int channel5 = 4;
int channel6 = 5;

// RiriFramework "Instruments"
RiriSequence kick; // Ground beat, ever present
RiriSequence snare; // Snare drum, Focus
RiriSequence hat; // Hi-hat, Focus
RiriSequence bass; // Bass, Focus (and Relax?)
RiriSequence arp; // Arpeggiator, Relax
RiriSequence pad; // Pad, Relax 

/*
*	Setup Sketch
*/

void setup() {
	// Sketch Setup
	size(WIDTH, HEIGHT);
	frameRate(60);
	// MidiBus Setup
	MidiBus.list();
	mb = new MidiBus(this, -1, MIDI_PORT_OUT);
	mb.sendTimestamps();
}

/*
*	Draw Loop
*/

void draw() {
	background(0);
	// Debug
	text("Focus/Relax: "+focusRelaxLevel, 0, HEIGHT - 15, WIDTH, HEIGHT);
	text("Pulse: "+pulse, WIDTH/4, HEIGHT - 15, WIDTH, HEIGHT);
	text("Beat: "+beat, 0, HEIGHT/2, WIDTH, HEIGHT);
	text("Measure: "+measure, 0, HEIGHT/2 + 15, WIDTH, HEIGHT);
	text("Phase: "+phase, 0, HEIGHT/2 + 30, WIDTH, HEIGHT);
	text("Grain: "+grain, WIDTH/4, HEIGHT/2, WIDTH, HEIGHT);
	text("BPM: "+bpm, WIDTH/4, HEIGHT/2 + 15, WIDTH, HEIGHT);
	text("Pitch: "+pitch, WIDTH/4, HEIGHT/2 + 30, WIDTH, HEIGHT);
	// Play Music
	if (playing) {
		playMusic();
	}
}

/*
*	Keyboard Input
*/

void keyPressed() {
	switch (key) {
		case ' ':
			if (!playing)
				setupMusic();
			else 
				stopMusic();
			break;
		case 'q': 
			addFocus(5);
			break;
		case 'a':
			addRelax(5);
			break;
		case 'w':
			upPulse(5);
			break;
		case 's':
			downPulse(5);
			break;
		default:
			break;
	}
}

/*
*	Playing Music
*/

void setupMusic() {
	// Reset song position
	beat = 0;
	measure = 0;
	phase = 1;
	setPhaseKey();
	// Setup the instruments
	kick = new RiriSequence(channel1);
	createKickMeasure();
	snare = new RiriSequence(channel2);
	hat = new RiriSequence(channel3);
	bass = new RiriSequence(channel4);
	arp = new RiriSequence(channel5);
	createRestMeasure(arp);
	pad = new RiriSequence(channel6);
	createRestMeasure(pad);
	// Start all instruments
	kick.start();
	arp.start();
	pad.start();
	// Start playing the song
	playing = true;
}

void playMusic() {
	// Get current time
	mils = millis();
	// Beat Change
	if (mils > lastMils + beatsToMils(1)) {
		updateLevelHistory();
		updateBpmHistory();
		if (beat == BEATS_PER_MEASURE) {
			beat = 1;
			// Measure Change
			if (measure == MEASURES_PER_PHASE) {
				measure = 1;
				if (phase == PHASES_PER_SONG) {
					// We're done!
					stopMusic();
				}
				else {
					phase++;
				}
			}
			else if (measure == MEASURES_PER_PHASE - 1) {
				// Prepare for the next phase
				setPhaseKey();
				measure++;
			}
			else {
				measure++;
			}
		}
		else if (beat == BEATS_PER_MEASURE - 1) {
			// Prepare the next measure
			setMeasureGrain();
			setMeasureBPM();
			createMeasure();
			beat++;
		}
		else {
			beat++;
		}
		// Update the time
		lastMils = millis();
	}
}

void stopMusic() {
	// Stop all instruments
	kick.quit();
	// Stop playing the song
	playing = false;
}

void createMeasure() {
	// Kick drum
	createKickMeasure();
	// Arp
	createArpMeasure();
	// Pad
	createPadMeasure();
}

void createRestMeasure(RiriSequence seq) {
	seq.addRest(beatsToMils(BEATS_PER_MEASURE));
}

void createKickMeasure() {
	kick.addNote(36, 100, beatsToMils(1));
	for (int i = 0; i < BEATS_PER_MEASURE - 1; i++) {
		kick.addNote(36, 80, beatsToMils(1));
	}
}

void createArpMeasure() {
	// If Relax is active, play the Arp
	if (level <= 0) {
		int interval = beatsToMils(beats[grain]);
		for (int i = 0; i < BEATS_PER_MEASURE / beats[grain]; i++) {
				int p1 = pitch + scale[(int) random(0, scale.length)];
				arp.addNote(p1, 80, interval);
			} 
		/*
		// Arp - Grain 0
		if (grain == 0) {
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				int p1 = pitch + scale[(int) random(0, scale.length)];
				arp.addNote(p1, 80, interval);
			} 
		}
		// Arp - Grain 1
		else if (grain == 1) {
			for (int i = 0; i < BEATS_PER_MEASURE * 2; i++) {
				int p1 = pitch + scale[(int) random(0, scale.length)];
				arp.addNote(p1, 80, interval);
			} 
		}
		// Arp - Grain 2
		else if (grain == 2) {
			for (int i = 0; i < BEATS_PER_MEASURE * 4; i++) {
				int p1 = pitch + scale[(int) random(0, scale.length)];
				arp.addNote(p1, 80, interval);
			} 
		}
		// Arp - Grain 3
		else {
			for (int i = 0; i < BEATS_PER_MEASURE * 8; i++) {
				int p1 = pitch + scale[(int) random(0, scale.length)];
				arp.addNote(p1, 80, interval);
			} 
		}
		*/
	}
	// If not, rest
	else {
		createRestMeasure(arp);
	}
}

void createPadMeasure() {
	// If Relax is active, play the pad
	if (level <= 0) {
		// Pad - Grain 0 and Grain 1
		if (grain <= 1) {
			int p1 = pitch - 12;
			int p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c1 = new RiriChord(channel6);
			c1.addNote(p1, 80, beatsToMils(beats[0]*4));
			c1.addNote(p2, 80, beatsToMils(beats[0]*4));
			pad.addChord(c1);
		}
		// Pad - Grain 2
		else if (grain == 2) {
			int p1 = pitch - 12;
			int p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c1 = new RiriChord(channel6);
			c1.addNote(p1, 80, beatsToMils(beats[1]*4));
			c1.addNote(p2, 80, beatsToMils(beats[1]*4));
			p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c2 = new RiriChord(channel6);
			c2.addNote(p1, 80, beatsToMils(beats[1]*4));
			c2.addNote(p2, 80, beatsToMils(beats[1]*4));
			pad.addChord(c1);
			pad.addChord(c2);
		}
		// Pad - Grain 3
		else {
			int p1 = pitch - 12;
			int p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c1 = new RiriChord(channel6);
			c1.addNote(p1, 80, beatsToMils(beats[2]*4));
			c1.addNote(p2, 80, beatsToMils(beats[2]*4));
			p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c2 = new RiriChord(channel6);
			c2.addNote(p1, 80, beatsToMils(beats[2]*4));
			c2.addNote(p2, 80, beatsToMils(beats[2]*4));
			p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c3 = new RiriChord(channel6);
			c3.addNote(p1, 80, beatsToMils(beats[2]*4));
			c3.addNote(p2, 80, beatsToMils(beats[2]*4));
			p2 = pitch + scale[(int) random(1, scale.length)] - 12;
			RiriChord c4 = new RiriChord(channel6);
			c4.addNote(p1, 80, beatsToMils(beats[2]*4));
			c4.addNote(p2, 80, beatsToMils(beats[2]*4));
			pad.addChord(c1);
			pad.addChord(c2);
			pad.addChord(c3);
			pad.addChord(c4);
		}
	}
	// If not, rest
	else {
		createRestMeasure(pad);
	}
}

/*
*	Utils
*/

// Get the length of a beat in milliseconds
int beatsToMils(float beats){
  // (one second split into single beats) * # needed
  float convertedNumber = (60000 / bpm) * beats;
  return (int) convertedNumber;
}

// Adjust the Focus and Relax values
void addFocus(int i) {
	focusRelaxLevel += i;
	if (focusRelaxLevel > MAX_FOCUS) {
		focusRelaxLevel = MAX_FOCUS;
	}
}

void addRelax(int i) {
	focusRelaxLevel -= i;
	if (focusRelaxLevel < MAX_RELAX) {
		focusRelaxLevel = MAX_RELAX;
	}
}

// Adjust the pulse value
void upPulse(int i) {
	pulse += i;
}

void downPulse(int i) {
	pulse -= i;
}

// Set the grain for the current measure
void setMeasureGrain() {
	// Get the average focusRelaxLevel
	float val = 0;
	for (int i = 0; i < levelHist.size(); i++) {
		val += levelHist.get(i);
	}
	val = val/levelHist.size();
	// Set level
	level = (int) val;
	// Set the grain
	val = abs(val);
	if (val < 20) {
		grain = 0;
	}
	else if (val >= 20 && val < 50) {
		grain = 1;
	}
	else if (val >= 50 && val < 80) {
		grain = 2;
	}
	else if (val >= 80) {
		grain = 3;
	}
	else {
		grain = 0; // Iunno
	}
}

// Get the beat length of the current grain
float grainToBeat() {
	return beats[grain];
}

// Get the millisecond length of the current grain
int grainToMillis() {
	return beatsToMils(grainToBeat());
}

// Set the BPM for the next measure
void setMeasureBPM() {
	// Get the average BPM
	float val = 0; 
	for (int i = 0; i < pulseHist.size(); i++) {
		val += pulseHist.get(i);
	}
	val = val/pulseHist.size();
	bpm = (int) val;
}

// Set the key for the next phase
void setPhaseKey() {
	if (phase == 1 || phase == 4) {
		pitch = PITCH_C;
	}
	else if (phase == 2) {
		pitch = PITCH_F;
	}
	else {
		pitch = PITCH_G;
	}
}

// Save the focusRelaxLevel to the history
void updateLevelHistory() {
	if (levelHist.size() == 4) {
		levelHist.remove(0);
	}
	levelHist.append(focusRelaxLevel);
}

// Save the pulse to the history
void updateBpmHistory() {
	if (pulseHist.size() == 4) {
		pulseHist.remove(0);
	}
	pulseHist.append(pulse);
}

/*
void updateGrainHistory() {
	if (grainHist.size() == 4) {
		grainHist.remove(0);
	}
	grainHist.append(grain);
}
*/
