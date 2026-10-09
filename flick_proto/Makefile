# flick_proto (JOO-193) — engine-less stick-gesture trick recognition
# Build the battery: g++ -std=c++17, then run it. Exit 0 = >=90% correct.

CXX = g++
CXXFLAGS = -std=c++17 -O2 -Wall -Wextra

flick_battery: flick_recognizer.cpp flick_recognizer.hpp battery.cpp
	$(CXX) $(CXXFLAGS) -o flick_battery flick_recognizer.cpp battery.cpp

run: flick_battery
	./flick_battery

clean:
	rm -f flick_battery

.PHONY: run clean