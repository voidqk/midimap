// (c) Copyright 2017, Sean Connelly (@voidqk), http://syntheti.cc
// MIT License
// Project Home: https://github.com/voidqk/midimap

#include <stdio.h>
#import <Foundation/Foundation.h>
#include <CoreMIDI/CoreMIDI.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <signal.h>

/*
void midiread(const MIDIPacketList *pkl, osxmidi_src_st *src, void *dummy){
	const MIDIPacket *p = &pkl->packet[0];
	for (int i = 0; i < pkl->numPackets; i++){
		// p->timeStamp, p->length, p->data
		p = MIDIPacketNext(p);
	}
}

bool osxmidi_src_open(int src_id, osxmidi_src_st *src){
	MIDIEndpointRef msrc = MIDIGetSource(src_id);
	if (msrc == 0)
		return false;

	MIDIPortRef pref = 0;
	OSStatus pst = MIDIInputPortCreate(client_ref, (CFStringRef)@"paralysis-ip",
		(MIDIReadProc)midiread, src, &pref);
	if (pst != 0)
		return false;

	OSStatus nst = MIDIPortConnectSource(pref, msrc, NULL);
	if (nst != 0){
		MIDIPortDispose(pref);
		return false;
	}
}

void osxmidi_src_close(osxmidi_src_st *src){
	MIDIPortDisconnectSource((MIDIPortRef)src->port, (MIDIEndpointRef)src->endpoint);
	MIDIPortDispose((MIDIPortRef)src->port);
}
*/

void midinotify(const MIDINotification *message, void *user){
	const char *msg = "Unknown";
	switch (message->messageID){
		case kMIDIMsgSetupChanged          : msg = "kMIDIMsgSetupChanged";           break;
		case kMIDIMsgObjectAdded           : msg = "kMIDIMsgObjectAdded";            break;
		case kMIDIMsgObjectRemoved         : msg = "kMIDIMsgObjectRemoved";          break;
		case kMIDIMsgPropertyChanged       : msg = "kMIDIMsgPropertyChanged";        break;
		case kMIDIMsgThruConnectionsChanged: msg = "kMIDIMsgThruConnectionsChanged"; break;
		case kMIDIMsgSerialPortOwnerChanged: msg = "kMIDIMsgSerialPortOwnerChanged"; break;
		case kMIDIMsgIOError               : msg = "kMIDIMsgIOError";                break;
	}
	fprintf(stderr, "Notify: %s\n", msg);
}

double ts_numer, ts_denom;
inline double ts_sec(double ts){
	return ts * ts_numer / ts_denom;
}

inline double ts_unsec(double ts){
	return ts * ts_denom / ts_numer;
}

inline double ts_now(){
	return ts_sec(mach_absolute_time());
}

bool done = false;
pthread_mutex_t done_mutex;
pthread_cond_t done_cond;
void catchdone(int dummy){
	done = true;
}

int main(int argc, char **argv){
	int result = 0;
	bool init_midi = false;

	// get timing information for converting timestamps to seconds
	{
		mach_timebase_info_data_t ts;
		mach_timebase_info(&ts);
		ts_numer = ts.numer;
		ts_denom = ts.denom * 1000000000.0;
	}

	// initialize MIDI
	MIDIClientRef client_ref;
	{
		OSStatus cst = MIDIClientCreate((CFStringRef)@"midimap", midinotify, NULL, &client_ref);
		if (cst != 0){
			fprintf(stderr, "Failed to initialize MIDI\n");
			result = 1;
			goto cleanup;
		}
		init_midi = true;
	}

	// list sources
	#define MAX_SOURCES 100
	int srcs_size = 0;
	MIDIEndpointRef srcs[MAX_SOURCES];
	const char *srcnames[MAX_SOURCES];
	{
		int len = MIDIGetNumberOfSources();
		if (len > MAX_SOURCES){
			fprintf(stderr,
				"Warning: System is reporting %d sources, but midimap only supports %d\n",
				len, MAX_SOURCES);
			len = MAX_SOURCES;
		}

		for (int i = 0; i < len; i++){
			MIDIEndpointRef src = MIDIGetSource(i);
			if (src == 0){
				fprintf(stderr, "Failed to get MIDI source %d\n", i + 1);
				continue;
			}
			int si = srcs_size++;
			srcs[si] = src;
			srcnames[si] = NULL;
			CFStringRef name = nil;
			if (MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) == 0 &&
				name != nil){
				srcnames[si] = [(NSString *)name UTF8String];
			}
			printf("Source %d: %s\n", i + 1, srcnames[si] ? srcnames[si] : "<No Name>");
		}
	}

	// wait for signal from Ctrl+C
	{
		printf("Press Ctrl+C to Quit\n");
		signal(SIGINT, catchdone);
		signal(SIGSTOP, catchdone);
		pthread_mutex_init(&done_mutex, NULL);
		pthread_cond_init(&done_cond, NULL);
		pthread_mutex_lock(&done_mutex);
		while (!done)
			pthread_cond_wait(&done_cond, &done_mutex);
		pthread_mutex_unlock(&done_mutex);
		pthread_mutex_destroy(&done_mutex);
		pthread_cond_destroy(&done_cond);
		printf("\nQuitting...\n");
	}

	cleanup:
	if (init_midi)
		MIDIClientDispose(client_ref);
	return result;
}
