@set @junk=1 /* vim:set ft=javascript:
@set @junk=
@cscript //nologo //e:jscript "%~dpn0.bat" %*
@exit /B %ERRORLEVEL%
*/

(function() {

var FSO = WScript.CreateObject("Scripting.FileSystemObject");
var WshShell = WScript.CreateObject("WScript.Shell");

// Extend builtin objects
Array.prototype.map = function(func) {
  var newArray = [];
  for (var i = 0; i < this.length; i++) {
    newArray.push(func(this[i]));
  }
  return newArray;
}
Array.prototype.filter = function(func) {
  var newArray = [];
  for (var i = 0; i < this.length; i++) {
    if (func(this[i])) {
      newArray.push(this[i]);
    }
  }
  return newArray;
}
Array.prototype.forEach = function(func) {
  for (var i = 0; i < this.length; i++) {
    func(this[i]);
  }
}
Array.prototype.indexOf = function(target) {
  for (var i = 0; i < this.length; i++) {
    if (this[i] === target) {
      return i;
    }
  }
  return -1;
}


// Wrapper of WshEnvironment
function Environment(wshEnv) {
  this.wshEnv = wshEnv;
}
Environment.PLACE_LIST = ["SYSTEM", "USER", "VOLATILE"];
Environment.prototype.get = function(name) {
  return this.wshEnv(name);
}
Environment.prototype.set = function(name, value) {
  this.wshEnv(name) = value;
}
Environment.prototype.remove = function(name) {
  this.wshEnv.Remove(name);
}
Environment.prototype.names = function() {
  return enumeratorToArray(this.wshEnv).map(function(item) {
    return item.substring(0, item.indexOf("="));
  });
}
Environment.prototype.toHash = function() {
  var hash = {};
  var names = this.names();
  for (var i = 0; i < names.length; i++) {
    var name = names[i];
    hash[name] = this.get(name);
  }
  return hash;
}


// Wsh things
function getEnv(place) {
  return new Environment(WshShell.Environment(place));
}

function getArglist() {
  var arglist = [];
  for (var i = 0; i < WScript.Arguments.length; i++) {
    arglist.push(WScript.Arguments(i));
  }
  return arglist;
}

function getOSVersion() {
  return WshShell.RegRead("HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\CurrentVersion");
}

function checkUAC() {
  return 6.0 <= getOSVersion();
}

var getStdIn = (function() {
  var stdin = null;
  return function() {
    if (stdin == null) {
      stdin = WScript.StdIn.ReadAll();
    }
    return stdin;
  };
})();

function readFile(file) {
  if (file === "-") {
    return getStdIn();
  }
  if (!FSO.FileExists(file)) {
    throw new Error("file not found: " + file);
  }
  if (FSO.getFile(file).Size == 0) {
    return "";
  }
  var READ_ONLY = 1;
  try {
    var textStream = FSO.OpenTextFile(file, READ_ONLY);
    if (textStream.AtEndOfStream) {
      return "";
    } else {
      return textStream.ReadAll();
    }
  } finally {
    if (textStream != null) {
      textStream.Close();
    }
  }
  throw new Error("failed to read the file: " + file);
}
function writeFile(file, content) {
  try {
    var textStream = FSO.CreateTextFile(file);
    textStream.Write(content);
  } finally {
    if (textStream != null) {
      textStream.Close();
    }
  }
}

function createTempFileName() {
   var TemporaryFolder = 2;
   var tempFolder = FSO.GetSpecialFolder(TemporaryFolder);
   return FSO.BuildPath(tempFolder, FSO.GetTempName());
}

function enumeratorToArray(obj) {
  var array = [];
  for (var e = new Enumerator(obj); !e.atEnd(); e.moveNext()) {
    array.push(e.item());
  }
  return array;
}

function restartByAdmin(args) {
  var tempFile = null;
  var outputFile = null;
  if (args.options.file === "-") {
    tempFile = createTempFileName();
    writeFile(tempFile, getStdIn());
    args.options.file = tempFile;
  }
  if (args.options.output == null) {
    outputFile = createTempFileName();
    args.options.output = outputFile;
  }
  var outputFileLastModified = FSO.FileExists(args.options.output)
    ? FSO.GetFile(args.options.output).DateLastModified
    : null;
  args.options.uac = createTempFileName();

  var objShell = WScript.CreateObject("Shell.Application");
  // Bypass the annoying UAC(User Account Control)
  var baseArgs = ["//nologo", "//e:jscript", WScript.ScriptFullName];
  var arglist = buildArglist(args);
  var arguments = baseArgs.concat(arglist).map(function(arg) {
        // XXX: Simple escape
        return '"' + arg.replace('"', '""') + '"';
      }).join(" ");
  objShell.ShellExecute("cscript.exe", arguments, "", "runas", 0);

  // Wait for the end of execution.
  while (!FSO.FileExists(args.options.uac)) {
    WScript.Sleep(10);
  }

  if (tempFile != null && FSO.FileExists(tempFile)) {
    FSO.DeleteFile(tempFile);
  }
  if (outputFile != null && FSO.FileExists(outputFile)) {
    WScript.StdOut.Write(readFile(outputFile));
    FSO.DeleteFile(outputFile);
  }
}


function parseArguments(arglist) {
  var args = {
    list: [],
    options: {
      file: null,
      help: false,
      list: false,
      names: false,
      output: null,
      place: Environment.PLACE_LIST[0],
      places: false,
      remove: false,
      uac: null,
      version: false
    }
  };
  var o = args.options;
  function setOption(opt) {
    switch(opt) {
      case "-f":
      case "--file":
        o.file = arglist.shift();
      break;
      case "-l":
      case "--list":
        o.list = true;
      break;
      case "-n":
      case "--names":
        o.names = true;
      break;
      case "-h":
      case "--help":
        o.help = true;
      break;
      case "-o":
      case "--output":
        o.output = arglist.shift();
      break;
      case "-p":
      case "--place":
        o.place = arglist.shift();
      break;
      case "--places":
        o.places = true;
      break;
      case "--remove":
        o.remove = true;
      break;
      case "-v":
      case "--version":
        o.version = true;
      break;
      case "--uac":
        o.uac = arglist.shift();
      break;
      default:
        throw new Error("unrecognized option: " + opt);
    }
  }
  while (arglist.length != 0) {
    var arg = arglist.shift();
    if (arg === "--") {
      args.list = args.list.concat(arglist);
      arglist = [];
    } else if (arg.match(/^--/)) {
      setOption(arg);
    } else if (arg.match(/^-/)) {
      for (var i = 1; i < arg.length; i++) {
        setOption("-" + arg.charAt(i));
      }
    } else {
      args.list.push(arg);
    }
  }
  return args;
}

function buildArglist(args) {
  var arglist = [];

  arglist.push("--place", args.options.place);
  ["file", "output", "uac"].forEach(function(option) {
    if (args.options[option]) {
      arglist.push("--" + option, args.options[option]);
    }
  });

  var optionList = [
    "help", "list", "names", "places", "remove", "version"
  ].filter(function(option) {
    return args.options[option];
  }).map(function(option) {
    return "--" + option;
  });
  arglist = arglist.concat(optionList);

  arglist.push("--");
  arglist = arglist.concat(args.list);

  return arglist;
}

function validateArgs(args) {
  if (3 <= args.list.length) {
    throw new Error("too many arguments.");
  }

  var place = (args.options.place || "").toUpperCase();
  if (Environment.PLACE_LIST.indexOf(place) < 0) {
    throw new Error("--place option must be one of the followings: " +
                    Environment.PLACE_LIST.join(", "));
  }

  if (args.list.length === 2) {
    if (args.options.file != null) {
      throw new Error("can not specify [value] and --file option in same time.");
    }
    if (args.options.remove) {
      throw new Error("can not specify [value] and --remove option in same time.");
    }
  }

  if (args.options.file != null && args.options.remove) {
    throw new Error("can not specify --file option and --remove option in same time.");
  }

}

function outputLines(lines, outputFile) {
  if (lines.length == 0) {
    return;
  }
  try {
    var stream = outputFile == null
      ? WScript.StdOut
      : FSO.CreateTextFile(outputFile);
    var lastLine = lines.pop();
    lines.forEach(function(line) {
      stream.WriteLine(line);
    });
    stream.Write(lastLine);
  } finally {
    if (stream != null) {
      stream.Close();
    }
  }
}

function getVersion() {
  return ["winenv version 1.0"];
}

function getUsage() {
  return [
    "Usage: winenv [options] [--] [varname [value]]",
    "",
    "  -f, --file {file}    set environment variable by the file content.",
    "  -h, --help           display this help.",
    "  -l, --list           display all environment variable with name=value.",
    "  -n, --names          display all environment variable names.",
    "  -p, --place {place}  specify the place of environment variable.",
    "                       [" + Environment.PLACE_LIST.join("|") + "]",
    '                       default to "' + Environment.PLACE_LIST[0] + '"',
    "      --remove         remove the variable.",
    "  -v, --version        display the version of winenv.",
  ];
}

function main() {
  var args = parseArguments(getArglist());
  validateArgs(args);

  function outputResult(lines) {
    outputLines(lines, args.options.output);
  }

  if (args.options.version) {
    outputResult(getVersion());
  }
  if (args.options.help) {
    outputResult(getUsage());
  }
  if (args.options.version || args.options.help) {
    return;
  }

  try {
    var env = getEnv(args.options.place);
    var resultLines = [];
    switch (args.list.length) {
      case 0:
        if (args.options.list) {
          resultLines = env.names().map(function(name) {
            return name + "=" + env.get(name);
          });
        } else if (args.options.names) {
          resultLines = env.names();
        } else if (args.options.places) {
          resultLines = Environment.PLACE_LIST;
        } else {
          resultLines = getUsage();
        }
      break;
      case 1:
        if (args.options.remove) {
          env.remove(args.list[0]);
        } else if (args.options.file != null) {
          env.set(args.list[0], readFile(args.options.file));
        } else {
          resultLines = [env.get(args.list[0])];
        }
      break;
      case 2:
        env.set(args.list[0], args.list[1]);
      break;
    }

    outputResult(resultLines);

  } catch (e) {
    // 70 == Permission denided
    // 5(TypeError) is thrown by "--remove" with unknown reason.
    var errorNumber = e.number & 0xFFFF;
    if ((errorNumber === 5 || errorNumber === 70) && args.options.uac == null && checkUAC()) {
      restartByAdmin(args);
      return;
    }
    throw e;
  } finally {
    if (args.options.uac != null) {
      // Mark as End
      writeFile(args.options.uac, "");
    }
  }
}


try {
  main();
  WScript.Quit(0);
} catch (e) {
  WScript.StdErr.WriteLine("Error: " + e.message);
  WScript.Quit(1);
}

}).call(this);
