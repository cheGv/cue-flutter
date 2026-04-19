function startSpeechRecognition(onResult, onEnd) {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) { onEnd(); return; }
  window._cueRecognition = new SpeechRecognition();
  window._cueRecognition.continuous = false;
  window._cueRecognition.interimResults = false;
  window._cueRecognition.lang = 'en-IN';
  window._cueRecognition.onresult = (e) => onResult(e.results[0][0].transcript);
  window._cueRecognition.onerror = () => onEnd();
  window._cueRecognition.onend = () => onEnd();
  window._cueRecognition.start();
}
function stopSpeechRecognition() {
  if (window._cueRecognition) window._cueRecognition.stop();
}
