# Speech benchmark

Each `.json` file here is one recording: what was really said (`reference`, checked by a person)
and what each listener heard (`heard.device`, `heard.cloud`). Words are `[text, start, end]` in
seconds of the recording.

`SpeechBenchmarkTests.benchmarkReport` scores every file on every CI run and prints word error
rate, start-time error and filler recall per listener. Change the engine, read the numbers.

To add a real recording: in the app, open a clip's transcript and use **Export speech sample**.
Fix the `reference` words and times by hand, then save the file here.
