/** Abstraction for structured the original project automation error logging. */
public interface VJErrorLogger {
    void error(String component, String action, String message,
        Exception exceptionValue, Id recordId, List<String> tags);
}