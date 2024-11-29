package io.github.mmhelloworld.idrisjvm.assembler;

import io.github.mmhelloworld.idrisjvm.runtime.Directories;
import io.github.mmhelloworld.idrisjvm.runtime.Runtime;
import org.objectweb.asm.ClassWriter;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Optional;
import java.util.Properties;
import java.util.Set;
import java.util.stream.Stream;

import static java.io.File.pathSeparator;
import static java.lang.ClassLoader.getSystemClassLoader;
import static java.lang.String.format;
import static java.lang.Thread.currentThread;
import static java.nio.file.Files.createTempDirectory;
import static java.nio.file.Files.newOutputStream;
import static java.util.Arrays.asList;
import static java.util.concurrent.TimeUnit.SECONDS;
import static java.util.stream.Collectors.toList;

public final class AsmGlobalState {
    private static final String RUNTIME_JAR_NAME;
    private static final List<String> JAVA_OPTIONS = getJavaOptions();
    private static final int IDRIS_REPL_TIMEOUT = Integer.parseInt(getProperty("IDRIS_REPL_TIMEOUT", "30"));
    private static final int BUFFER_SIZE = 10 * 1024;

    static {
        try {
            RUNTIME_JAR_NAME = getRuntimeJarName();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    private final Map<String, Object> functions;
    private final Set<String> constructors;
    private final String programName;
    private final Map<String, Object> fcAndDefinitionsByName;
    private final Map<String, Assembler> assemblers;

    public <T> AsmGlobalState(String programName,
                              Map<String, Object> fcAndDefinitionsByName) {
        this.programName = programName;
        functions = new HashMap<>();
        constructors = new HashSet<>();
        assemblers = new HashMap<>();
        this.fcAndDefinitionsByName = fcAndDefinitionsByName;
    }

    private static void copyRuntimeClasses(String outputDirectory) {
        String packageName = Runtime.class.getPackage().getName();
        String packagePath = packageName.replaceAll("[.]", "/");
        ClassLoader classLoader = getSystemClassLoader();
        InputStream stream = classLoader.getResourceAsStream(packagePath);
        BufferedReader reader = new BufferedReader(new InputStreamReader(stream));
        reader.lines()
            .filter(className -> className.endsWith(".class"))
            .forEach(className -> copyRuntimeClass(classLoader, className, packagePath, outputDirectory));
    }

    private static void copyRuntimeClass(ClassLoader classLoader, String className, String packagePath,
                                         String outputDirectory) {
        Path outputPath = Paths.get(outputDirectory, packagePath, className);
        outputPath.getParent().toFile().mkdirs();
        try (InputStream inputStream = new BufferedInputStream(classLoader
            .getResourceAsStream("runtimeclasses/" + packagePath + "/" + className));
             OutputStream outputStream = new BufferedOutputStream(newOutputStream(outputPath))) {
            copy(inputStream, outputStream);
        } catch (IOException exception) {
            throw new RuntimeException(exception);
        }
    }

    private static List<String> getJavaOptions() {
        String javaOpts = getProperty("JAVA_OPTS", "-Xss8m");
        return asList(javaOpts.split("\\s+"));
    }

    private static String getProperty(String propertyName, String defaultValue) {
        String value = System.getProperty(propertyName, System.getenv(propertyName));
        return value == null ? defaultValue : value;
    }

    private static void copy(InputStream inputStream, OutputStream outputStream) throws IOException {
        byte[] buffer = new byte[BUFFER_SIZE];
        int length;
        while ((length = inputStream.read(buffer)) > 0) {
            outputStream.write(buffer, 0, length);
        }
        outputStream.flush();
    }

    private static String getRuntimeJarName() throws IOException {
        ClassLoader classLoader = currentThread().getContextClassLoader();
        Properties properties = new Properties();
        properties.load(classLoader.getResourceAsStream("project.properties"));
        return format("idris-jvm-runtime-%s.jar", properties.getProperty("project.version"));
    }

    public synchronized void addFunction(String name, Object value) {
        functions.put(name, value);
    }

    public synchronized Object getFunction(String name) {
        return functions.get(name);
    }

    public synchronized Assembler getAssembler(String name) {
        return assemblers.computeIfAbsent(name, key -> new Assembler());
    }

    public String getProgramName() {
        return programName;
    }

    public synchronized boolean hasConstructor(String name) {
        return constructors.contains(name);
    }

    public synchronized void addConstructor(String name) {
        constructors.add(name);
    }

    public void classCodeEnd(String outputDirectory, String outputFile, String mainClass)
        throws IOException, InterruptedException {
        String normalizedOutputDirectory = outputDirectory.isEmpty()
            ? createTempDirectory("idris-jvm-repl").toString() : outputDirectory;
        String classDirectory = outputDirectory.isEmpty()
            ? normalizedOutputDirectory : normalizedOutputDirectory + File.separator + outputFile + "_app";
        getClassNameAndClassWriters()
            .forEach(classNameAndClassWriter ->
                writeClass(classNameAndClassWriter.getKey(), classNameAndClassWriter.getValue(), classDirectory));
        String mainClassNoSlash = mainClass.replace('/', '.');
        if (outputDirectory.isEmpty()) {
            copyRuntimeClasses(normalizedOutputDirectory);
            interpret(mainClassNoSlash, normalizedOutputDirectory);
        } else {
            new File(classDirectory).mkdirs();
            copyRuntimeClasses(classDirectory);
            Assembler.createExecutable(normalizedOutputDirectory, outputFile, mainClassNoSlash);
        }
    }

    public void interpret(String mainClass, String outputDirectory) throws IOException, InterruptedException {
        String classpath = String.join(pathSeparator, outputDirectory,
            outputDirectory + File.separator + RUNTIME_JAR_NAME, System.getProperty("java.class.path"));
        List<String> command = Stream.concat(
                Stream.concat(Stream.of("java"), JAVA_OPTIONS.stream()),
                Stream.of("-cp", classpath, mainClass))
            .collect(toList());
        new ProcessBuilder(command)
            .directory(new File((String) Directories.getWorkingDirectory()))
            .inheritIO()
            .start()
            .waitFor(IDRIS_REPL_TIMEOUT, SECONDS);
    }

    public void writeClass(String className, ClassWriter classWriter, String outputClassFileDir) {
        File outFile = new File(outputClassFileDir, className + ".class");
        new File(outFile.getParent()).mkdirs();
        try (OutputStream out = newOutputStream(outFile.toPath())) {
            out.write(classWriter.toByteArray());
        } catch (Exception exception) {
            exception.printStackTrace();
        }
    }

    private Stream<Entry<String, ClassWriter>> getClassNameAndClassWriters() {
        return assemblers.values().parallelStream()
            .map(Assembler::classInitEnd)
            .flatMap(assembler -> assembler.getClassWriters().entrySet().stream());
    }

    public Object getFcAndDefinition(String name) {
        return Optional.ofNullable(fcAndDefinitionsByName.get(name))
            .orElseThrow(() -> new IdrisJvmException("Unable to find function " + name));
    }
}
