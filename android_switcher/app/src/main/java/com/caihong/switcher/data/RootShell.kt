package com.caihong.switcher.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

data class ShellResult(
    val exitCode: Int,
    val stdout: String,
    val stderr: String,
) {
    val isSuccess: Boolean get() = exitCode == 0
    val combinedOutput: String
        get() = listOf(stdout.trim(), stderr.trim()).filter { it.isNotEmpty() }.joinToString("\n")
}

object RootShell {
    private const val TIMEOUT_SECONDS = 8L

    suspend fun runRoot(command: String): ShellResult = withContext(Dispatchers.IO) {
        exec(listOf("su", "-c", command))
    }

    suspend fun runUser(vararg args: String): ShellResult = withContext(Dispatchers.IO) {
        exec(args.toList())
    }

    fun quoteArg(arg: String): String = "'" + arg.replace("'", "'\"'\"'") + "'"

    private fun exec(command: List<String>): ShellResult {
        return try {
            val process = ProcessBuilder(command).start()
            val stdoutBytes = ByteArrayOutputStream()
            val stderrBytes = ByteArrayOutputStream()

            val outThread = drainAsync(process.inputStream, stdoutBytes)
            val errThread = drainAsync(process.errorStream, stderrBytes)

            val finished = process.waitFor(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!finished) {
                process.destroyForcibly()
                outThread.join(300)
                errThread.join(300)
                return ShellResult(
                    exitCode = -1,
                    stdout = stdoutBytes.toString(StandardCharsets.UTF_8.name()),
                    stderr = "命令执行超时 (${TIMEOUT_SECONDS}s)",
                )
            }
            outThread.join(500)
            errThread.join(500)
            ShellResult(
                exitCode = process.exitValue(),
                stdout = stdoutBytes.toString(StandardCharsets.UTF_8.name()),
                stderr = stderrBytes.toString(StandardCharsets.UTF_8.name()),
            )
        } catch (t: Throwable) {
            ShellResult(
                exitCode = -1,
                stdout = "",
                stderr = t.message ?: t.javaClass.simpleName,
            )
        }
    }

    private fun drainAsync(stream: InputStream, sink: ByteArrayOutputStream): Thread {
        return Thread {
            try {
                stream.use { input ->
                    val buffer = ByteArray(2048)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        sink.write(buffer, 0, read)
                    }
                }
            } catch (_: Throwable) {
            }
        }.apply { start() }
    }
}
