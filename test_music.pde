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
int MAX_FOCUS = 100;
int MAX_RELAX = -100;

// Grain - "Frequency" of notes, 0 = 1/4 notes, 1 = 1/8 notes, 2 = 1/16 notes, 3 = 1/32 notes
// Corresponds to Focus/Relax Level (0 = 0 to 20, 1 = 20 to 50, 2 = 50 to 80, 3 = 80 to 100)
int grain = 0;
float[] beats = {1, 0.5, 0.25, 0.125};

// BPM - Beats per minute, corresponds to pulse (average over X measures)
int bpm = 60;

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
	text("BPM: "+bpm, WIDTH/4, HEIGHT - 15, WIDTH, HEIGHT);
	text("Beat: "+beat, 0, HEIGHT/2, WIDTH, HEIGHT);
	text("Measure: "+measure, 0, HEIGHT/2 + 15, WIDTH, HEIGHT);
	text("Phase: "+phase, 0, HEIGHT/2 + 30, WIDTH, HEIGHT);
	text("Grain: "+grain, WIDTH/4, HEIGHT/2, WIDTH, HEIGHT);
	text("Pitch: "+pitch, WIDTH/4, HEIGHT/2 + 15, WIDTH, HEIGHT);
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
			upHeartRate(5);
			break;
		case 's':
			downHeartRate(5);
			break;
		default:
			break;
	}
}

/*
*	Playing Music
*/

void setupMusic() {
	beat = 0;
	measure = 1;
	phase = 1;
	setPhaseKey();
	playing = true;
}

void playMusic() {
	// Get current time
	mils = millis();
	// Beat Change
	if (mils > lastMils + beatsToMils(1)) {
		if (beat == BEATS_PER_MEASURE) {
			beat = 1;
			// Measure Change
			setGrain();
			if (measure == MEASURES_PER_PHASE) {
				measure = 1;
				if (phase == PHASES_PER_SONG) {
					// We're done!
					stopMusic();
				}
				else {
					phase++;
				}
				// Phase Change
				setPhaseKey();
			}
			else {
				measure++;
			}
		}
		else {
			beat++;
		}
		// Update the time
		lastMils = mils;
	}
}

void stopMusic() {
	playing = false;
}

/*
*	Utils
*/

int beatsToMils(float beats){
  // (one second split into single beats) * # needed
  float convertedNumber = (60000 / bpm) * beats;
  return (int) convertedNumber;
}

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

void upHeartRate(int i) {
	bpm += i;
}

void downHeartRate(int i) {
	bpm -= i;
}

void setGrain() {
	int val = abs(focusRelaxLevel);
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

float grainToBeat() {
	return beats[grain];
}

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
