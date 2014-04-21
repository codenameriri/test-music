import themidibus.*;
import processing.serial.*;
import org.firmata.*;
import cc.arduino.*;
import java.util.Map;

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
int pulse = 80; // 65
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
int MEASURES_PER_PHASE = 4; //8
int beat = 0;
int BEATS_PER_MEASURE = 4;
int mils = millis();
int lastMils = mils;

// Music Stuff
int[] scale = {0, 2, 4, 7, 9}; // I, II, III, V, VI of a major scale
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

// MindFlex Serial things
int MINDFLEX_PORT = 0;
Serial mindFlex;
PrintWriter output;
int packetCount = 0;
int START_PACKET = 3;
int globalMax = 0;

// DataGen Properties
HashMap<String,Integer> inputSettings = new HashMap<String,Integer>();
DataGenerator dummyDataGenerator;
boolean useDummyData = false;

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
	// MindFlex
	println("Serial:");
	for (int i = 0; i < Serial.list().length; i++) {
	    println("[" + i + "] " + Serial.list()[i]);
	}
	try {
		mindFlex = new Serial(this, Serial.list()[MINDFLEX_PORT], 9600);
		mindFlex.bufferUntil(10);
		String date = day() + "_" + month() + "_" + year();
  		String time = "" + hour() + minute() + second();
		output = createWriter("brain_data/brain_data_out_"+date+"_"+time+".txt");
	}
	catch (Exception e) {
		useDummyData = true;
	}
	// DataGen
	inputSettings.put("brainwave", 1000);
	dummyDataGenerator = new DataGenerator(inputSettings);
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
		case 27: 
			output.flush();
			output.close();
			stopMusic();
			exit();
			break;
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
		case '1':
			// Test MIDI Mapping
			mb.sendNoteOn(channel6, 0, 80);
			mb.sendNoteOff(channel6, 0, 80);
			println("TEST");
			break;
		case '2':
			// Test Tempo change
			mb.sendNoteOn(6, 0, 80);
			mb.sendNoteOff(6, 0, 80);
			mb.sendNoteOn(7, 127, 80);
			mb.sendNoteOff(7, 127, 80);
			println("TEMPO");
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
	pitch = PITCH_C;
	// Setup the instruments
	createInstrumentsBeforePhase();
	createKickMeasure();
	createRestMeasure(snare);
	createRestMeasure(hat);
	createRestMeasure(bass);
	createRestMeasure(arp);
	createRestMeasure(pad);
	// Start all instruments
	kick.start();
	snare.start();
	hat.start();
	bass.start();
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
				// createInstrumentsBeforePhase();
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
			if (useDummyData) {
				String input = dummyDataGenerator.getInput("brainwave");
				calculateFocusRelaxLevel(input);
			}
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
	if (playing) {
		// Stop all instruments
		kick.quit();
		snare.quit();
		hat.quit();
		bass.quit();
		arp.quit();
		pad.quit();
		// Stop playing the song
		playing = false;
	}
}

void createMeasure() {
	// Kick drum
	createKickMeasure();
	// Snare drum
	createSnareMeasure();
	// Hat
	createHatMeasure();
	// Bass
	createBassMeasure();
	// Arp
	createArpMeasure();
	// Pad
	createPadMeasure();
}

void createInstrumentsBeforePhase() {
	kick = new RiriSequence(channel1);
	snare = new RiriSequence(channel2);
	hat = new RiriSequence(channel3);
	bass = new RiriSequence(channel4);
	arp = new RiriSequence(channel5);
	pad = new RiriSequence(channel6);
}

void createRestMeasure(RiriSequence seq) {
	seq.addRest(beatsToMils(BEATS_PER_MEASURE));
}

void createKickMeasure() {
	kick.addNote(36, 120, beatsToMils(1));
	for (int i = 0; i < BEATS_PER_MEASURE - 1; i++) {
		kick.addNote(36, 120, beatsToMils(1));
	}
}

void createSnareMeasure() {
	// If focus is active 
	if (level >= 0) {
		// Snare - Grain 0
		if (grain == 0) {
			createRestMeasure(snare);
		}
		// Snare - Grain 1
		else if (grain ==1) {
			// Play a note every other measure
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				if (i % 2 == 1) {
					snare.addNote(38, 120, beatsToMils(1));
				}
				else {
					snare.addRest(beatsToMils(1));
				}
			}
		}
		// Snare - Grain 2
		else if (grain == 2) {
			for (int i = 0; i < BEATS_PER_MEASURE / beats[1]; i++) {
				int r1 = round(random(0,1));
				if (r1 == 0) {
					snare.addNote(38, 120, beatsToMils(beats[1]));
				}
				else {
					snare.addRest(beatsToMils(beats[1]));
				}
			}
		}
		// Snare - Grain 3
		else {
			for (int i = 0; i < BEATS_PER_MEASURE / beats[2]; i++) {
				int r1 = round(random(0,1));
				if (r1 == 0) {
					snare.addNote(38, 120, beatsToMils(beats[2]));
				}
				else {
					snare.addRest(beatsToMils(beats[2]));
				}
			}
		}
	}
	else {
		createRestMeasure(snare);
	}
}

void createHatMeasure() {
	int close = 42;
	int open = 46;
	// If Focus is active, play the Hat
	if (level >= -19) {
		// Hat - Grain 0
		if (grain == 0) {
			// Play a closed note every other measure
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				if (i % 2 == 1) {
					hat.addNote(close, 120, beatsToMils(1));
				}
				else {
					hat.addRest(beatsToMils(1));
				}
			}
		}
		// Hat - Grain 1
		else if (grain == 1) {
			// Play a closed note every measure, end open
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				if (i == BEATS_PER_MEASURE - 1) {
					hat.addNote(close, 120, beatsToMils(.5));
					hat.addNote(open, 120, beatsToMils(.5));
				}
				else {
					hat.addNote(close, 120, beatsToMils(1));
				}
			}
		}
		// Hat - Grain 2
		else if (grain == 2) {
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				if (i % 2 == 1) {
					hat.addNote(close, 120, beatsToMils(.25));
					hat.addNote(close, 80, beatsToMils(.25));
					hat.addNote(close, 80, beatsToMils(.25));
					hat.addNote(open, 120, beatsToMils(.25));
				}
				else {
					hat.addNote(close, 120, beatsToMils(.25));
					hat.addNote(close, 80, beatsToMils(.25));
					hat.addNote(close, 80, beatsToMils(.25));
					hat.addNote(close, 80, beatsToMils(.25));
				}
			}
		}
		// Hat - Grain 3
		else {
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				hat.addNote(close, 120, beatsToMils(.25));
				hat.addNote(close, 80, beatsToMils(.25));
				hat.addNote(close, 80, beatsToMils(.25));
				hat.addNote(open, 120, beatsToMils(.25));
			}
		}
	}
	else {
		createRestMeasure(hat);
	}
}

void createBassMeasure() {
	// If Focus is active, play the Bass
	if (level >= 0) {
		int interval = beatsToMils(beats[grain]*2);
		// Random notes for now
		for (int i = 0; i < BEATS_PER_MEASURE / (beats[grain] * 2); i++) {
			int p1 = pitch + scale[(int) random(0, scale.length)] - 24;
			bass.addNote(p1, 80, interval);
		}
	}
	else {
		createRestMeasure(bass);
	}
}

void createArpMeasure() {
	// If Relax is active, play the Arp
	if (level <= 0) {
		int interval = beatsToMils(beats[grain]);
		/*for (int i = 0; i < BEATS_PER_MEASURE / beats[grain]; i++) {
			int p1 = pitch + scale[(int) random(0, scale.length)];
			arp.addNote(p1, 80, interval);
		}*/ 

		// Arp - Grain 0
		if (grain == 0) {
			// Random notes
			for (int i = 0; i < BEATS_PER_MEASURE; i++) {
				int p1 = pitch + scale[(int) random(0, scale.length)];
				arp.addNote(p1, 80, interval);
			} 
		}

		// Arp - Grain 1 or higher
		else {
			int arpNotes[];
			int count = 0;
			if (grain == 1) {
				// Arpeggiate with I and V
				int[] tmp = {pitch, pitch + scale[3]};
				arpNotes = tmp;
			}
			else if (grain == 2) {
				// Arpeggiate with I, III, and V
				int [] tmp = {pitch, pitch + scale[2], pitch + scale[3], pitch + scale[2]};
				arpNotes = tmp;
			}
			else {
				// Arpeggiate with I, II, III, V, and VI
				int [] tmp = {pitch, pitch + scale[1], pitch + scale[2], pitch + scale[3], pitch + scale[4], pitch + scale[3], pitch + scale[2], pitch + scale[1]};
				arpNotes = tmp;
			}
			// RELIES ON 4/4 LOLOL
			int loops = 2;
			int howMany = (int) (BEATS_PER_MEASURE / beats[grain]);
			int octave = 0;
			//println(loops * howMany);
			for (int i = 0; i < howMany; i++) {
				arp.addNote(arpNotes[count] + octave, 80, interval);
				if (count == arpNotes.length - 1) {
					count = 0;
					octave = (octave == 12) ? 0 : 12;
				}
				else {
					count++;
				}
			}
		}
	}
	// If not, rest
	else {
		createRestMeasure(arp);
	}
}

void createPadMeasure() {
	// If Relax is active, play the pad
	if (level <= 19) {
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
	int p = phase + 1;
	println(p);
	if (p == PHASES_PER_SONG - 2) {
		pitch = PITCH_F;
	}
	else if (p == PHASES_PER_SONG - 1) {
		pitch = PITCH_G;
	}
	else {
		pitch = PITCH_C;
	}
	println(pitch);
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

/*
*	MindFlex Input
*/

void serialEvent(Serial p) {
	// Read in the data
	String input;
	try {
		input = p.readString().trim();
		print("Received string over serial: ");
		println(input);
		output.println(input);
	}
	catch (Exception e) {
		input = dummyDataGenerator.getInput("brainwave");
		useDummyData = true;
	}
	calculateFocusRelaxLevel(input);
}

void calculateFocusRelaxLevel(String input) {
	// Parse the data
	boolean goodRead = false;
	if (input.indexOf("ERROR:") != -1 || input.length() == 0) {
		println("bad");
		goodRead = false;
	}
	else {
		println("good");
		goodRead = true;
	}
	if (goodRead) {
		String[] brainData = input.split(",");
		int[] intData = new int[brainData.length];
		if (brainData.length > 8) {
			packetCount++;
			if (packetCount > START_PACKET) {
				for (int i = 0; i < brainData.length; i++) {
					String strVal = brainData[i].trim();
					int intVal = Integer.parseInt(strVal);
					// 0 THE DATA WHEN SIGNAL SUCKS
					if ((Integer.parseInt(brainData[0]) == 200) && (i > 2)) {
			          	intVal = 0;
			        }
			        intData[i] = intVal;
				}
			}
		}

		// Format the data
		int min = -1; 
		int max = -1;
		for (int i = 3; i < intData.length; i++) {
			if (max < 0 || intData[i] > max) {
				max = intData[i];
				if (max > globalMax) {
					globalMax = max;
				}
			}
			if (min < 0 || intData[i] < min) {
				min = intData[i];
			}
		}
		println("MIN " + min + " MAX " + max);

		int[] tmp = new int[intData.length - 3];
		for (int i = 3; i < intData.length; i++) {
			//tmp[i-3] = (int) map(intData[i], min, max, 0, 100);
			tmp[i-3] = (int) map(intData[i], 0, globalMax, 0, 100);
		}

		// Interpret the data
		int focusVal = 0;
		int relaxVal = 0;
		float newLevel = 0;
		for (int i = 1; i < tmp.length; i++) {
			if (i < tmp.length/2) {
				relaxVal += tmp[i];
			}
			else {
				focusVal += tmp[i];
			}
		}
		focusVal = (int) (focusVal / 4);
		relaxVal = (int) (relaxVal / 4);

		// Set the brain level
		newLevel = focusVal - relaxVal;
		// focusRelaxLevel = (int) newLevel;
		//focusRelaxLevel += (int) (newLevel / 4);
		focusRelaxLevel += (int) newLevel;
		if (focusRelaxLevel > MAX_FOCUS) {
			focusRelaxLevel = MAX_FOCUS;
		}
		else if (focusRelaxLevel < MAX_RELAX) {
			focusRelaxLevel = MAX_RELAX;
		}
		//newLevel = map(focusVal - relaxVal, 0, 100, -100, 100);
		println("NEW LEVEL: "+newLevel);
	}
	else {
		// Do something
	}
}