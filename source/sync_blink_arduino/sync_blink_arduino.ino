// Which digital input pin will the signal be exported on:
const int led_pin = 8;
// How long should each pulse be (ms):
const long onTime = 80;
// How long between pulse onsets (ms):
const int period = 1000*10;

// How long should pulses stay low (calculated):
const long offTime = period - onTime;

void setup() {
  // Set up digital output pin
  pinMode(led_pin, OUTPUT);
}

void loop() {
  // Send pulse high
  digitalWrite(led_pin, HIGH);
  // Wait for onTime to elapse
  delay(onTime);
  // Send pulse low
  digitalWrite(led_pin, LOW);
  // Wait for offTime to elapse
  delay(offTime);
}
