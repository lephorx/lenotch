using System;
using NAudio.Dsp;
using NAudio.Wave;

namespace Lenotch.Services;

/// Levels of the system's audio output (WASAPI loopback, no permission needed) in
/// four bands, for the equalizer bars. Runs only while switched on and playing.
public sealed class AudioVisualizer : IDisposable
{
    private const int FftExponent = 10;
    private const int FftSize = 1 << FftExponent;
    private static readonly (double low, double high)[] Bands = { (60, 250), (250, 1000), (1000, 4000), (4000, 12000) };

    private WasapiLoopbackCapture? capture;
    private readonly float[] samples = new float[FftSize];
    private int sampleCount;
    private readonly float[] levels = new float[Bands.Length];
    private DateTime lastSignal = DateTime.MinValue;
    private readonly object gate = new();

    /// 0...1 per band.
    public float[] Levels
    {
        get { lock (gate) return (float[])levels.Clone(); }
    }

    /// Real sound came through recently (otherwise the bars use their stand-in animation).
    public bool HasSignal => (DateTime.UtcNow - lastSignal).TotalSeconds < 0.5;

    public bool IsRunning
    {
        get => capture != null;
        set
        {
            if (value == IsRunning) return;
            if (value) Start(); else Stop();
        }
    }

    private void Start()
    {
        try
        {
            capture = new WasapiLoopbackCapture();
            capture.DataAvailable += OnData;
            capture.RecordingStopped += (_, _) => { };
            capture.StartRecording();
        }
        catch (Exception)
        {
            capture?.Dispose();
            capture = null;
        }
    }

    private void Stop()
    {
        var old = capture;
        capture = null;
        if (old == null) return;
        try { old.StopRecording(); } catch (Exception) { }
        old.Dispose();
        lock (gate) Array.Clear(levels);
    }

    private void OnData(object? sender, WaveInEventArgs args)
    {
        var format = (sender as WasapiLoopbackCapture)?.WaveFormat;
        if (format == null || format.Encoding != WaveFormatEncoding.IeeeFloat || format.BitsPerSample != 32) return;
        var channels = format.Channels;
        var frameBytes = 4 * channels;
        for (var offset = 0; offset + frameBytes <= args.BytesRecorded; offset += frameBytes)
        {
            float sum = 0;
            for (var c = 0; c < channels; c++) sum += BitConverter.ToSingle(args.Buffer, offset + c * 4);
            samples[sampleCount++] = sum / channels;
            if (sampleCount == FftSize)
            {
                Analyse(format.SampleRate);
                sampleCount = 0;
            }
        }
    }

    private void Analyse(int sampleRate)
    {
        var buffer = new Complex[FftSize];
        for (var i = 0; i < FftSize; i++)
        {
            buffer[i].X = (float)(samples[i] * FastFourierTransform.HannWindow(i, FftSize));
            buffer[i].Y = 0;
        }
        FastFourierTransform.FFT(true, FftExponent, buffer);
        var binWidth = sampleRate / (double)FftSize;
        var next = new float[Bands.Length];
        var anySignal = false;
        for (var band = 0; band < Bands.Length; band++)
        {
            var (low, high) = Bands[band];
            int first = Math.Max(1, (int)(low / binWidth)), last = Math.Min(FftSize / 2 - 1, (int)(high / binWidth));
            double energy = 0;
            for (var bin = first; bin <= last; bin++)
                energy = Math.Max(energy, Math.Sqrt(buffer[bin].X * buffer[bin].X + buffer[bin].Y * buffer[bin].Y));
            var db = 20 * Math.Log10(Math.Max(energy, 1e-9));
            // About -70 dB is silence, -10 dB loud.
            next[band] = (float)Math.Clamp((db + 70) / 60, 0, 1);
            if (next[band] > 0.05) anySignal = true;
        }
        lock (gate)
        {
            for (var i = 0; i < levels.Length; i++)
            {
                // Rise fast, fall gently.
                levels[i] = next[i] > levels[i] ? next[i] : levels[i] * 0.75f + next[i] * 0.25f;
            }
        }
        if (anySignal) lastSignal = DateTime.UtcNow;
    }

    public void Dispose() => Stop();
}
