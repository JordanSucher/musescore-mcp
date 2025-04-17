import QtQuick 2.9
import MuseScore 3.0

MuseScore {
    id: root
    menuPath: "Plugins.MuseScore API Server"
    description: "Exposes MuseScore API via WebSocket"
    version: "1.0"
    
    property var clientConnections: []
    
    // Global state to track selection position
    property var selectionState: ({
        startStaff: 0,
        endStaff: 0,
        startTick: 0,
        elements: []
    });

    function processMessage(message, clientId) {
        console.log("Received message: " + message);
        try {
            var command = JSON.parse(message);
            var result = processCommand(command);
            api.websocketserver.send(clientId, JSON.stringify({
                status: "success",
                result: result
            }));
        } catch (e) {
            console.log("Error processing command: " + e.toString());
            api.websocketserver.send(clientId, JSON.stringify({
                status: "error",
                message: e.toString()
            }));
        }
    }

    // Multi-action commands

    function processSequence(params) {
        if (!curScore) return { error: "No score open" };

        if (!params.sequence) {
            return { error: "No sequence specified" };
        }

        var validCommands = [
            "getScore",
            "addNote",
            "addRest",
            "addTuplet",
            "appendMeasure",
            "deleteSelection",
            "getCursorInfo",
            "goToMeasure",
            "nextElement",
            "prevElement",
            "selectCurrentMeasure",
            "processSequence",
            "insertMeasure",
            "goToFinalMeasure",
            "goToBeginningOfScore",
            "setTimeSignature"
        ]

        try {
            // process commands in order
            for (var i = 0; i < params.sequence.length; i++) {
                if (!validCommands.includes(params.sequence[i].action)) {
                    throw new Error("Invalid command: " + params.sequence[i].action + " Valid commands: " + validCommands.join(", "));
                }
                processCommand(params.sequence[i]);
            }

            return { success: true, message: "Sequence processed", currentSelection: selectionState, currentScore: getScoreSummary() };
        } catch (e) {
            return { error: e.toString() };
        }
    }
    
    function processCommand(command) {
        console.log("Processing command: " + command.action);
        switch(command.action) {
            // Basic score operations
            case "getScore":
                return getScore(command.params);
            case "syncStateToSelection":
                return syncStateToSelection();
                
            // Sequence
            case "processSequence":
                return processSequence(command.params);

            // Note and measure operations
            case "addNote":
                return addNote(command.params);
            case "addRest":
                return addRest(command.params);
            case "addTuplet":
                return addTuplet(command.params);
            case "appendMeasure":
                return appendMeasure(command.params);
            case "deleteSelection":
                return deleteSelection(command.params);
                
            // Cursor and navigation
            case "getCursorInfo":
                return getCursorInfo(command.params);
            case "goToMeasure":
                return goToMeasure(command.params);
            case "nextElement":
                return nextElement(command.params);
            case "prevElement":
                return prevElement(command.params);
            case "selectCurrentMeasure":
                return selectCurrentMeasure(command.params);
            case "insertMeasure":
                return insertMeasure(command.params);
            case "goToFinalMeasure":
                return goToFinalMeasure(command.params);
                
            // Staff and instrument operations
            case "addInstrument":
                return addInstrument(command.params);
            case "setStaffMute":
                return setStaffMute(command.params);
            case "setInstrumentSound":
                return setInstrumentSound(command.params);
                
            // Time signature and tempo
            case "setTimeSignature":
                return setTimeSignature(command.params);
            case "setTempo":
                return setTempo(command.params);
                
                
            // Utility
            case "undo":
                return undo();
            case "ping":
                return "pong";
            case "goToBeginningOfScore":
                var response = initCursorState();
                return { 
                    success: true, 
                    message: response, 
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            default:
                throw new Error("Unknown command: " + command.action);
        }
    }
    
    // Score Management

    // Undo

    function undo() {
        if (!curScore) return { error: "No score open" };
        
        curScore.startCmd();
        try {
            cmd("undo");
            curScore.endCmd();
            return { success: true, message: "Undo successful", currentSelection: selectionState, currentScore: getScoreSummary() };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Create and position a cursor
    function createCursor(params) {
        if (!curScore) throw new Error("No score open");
        
        // If no params provided, use saved state
        if (!params || Object.keys(params).length === 0) {
            params = selectionState;
        }
        
        var cursor = curScore.newCursor();
        
        // Set cursor to sync with the score's visible input state
        cursor.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE;
        
        // Set track (staff and voice)
        if (params.startStaff !== undefined) {
            cursor.staffIdx = params.startStaff;
        }
        if (params.voice !== undefined) {
            cursor.voice = params.voice;
        }
        
        // Position the cursor
        if (params.rewindMode !== undefined) {
            // Use rewindMode: 0 (score start), 1 (selection start), 2 (selection end)
            cursor.rewind(params.rewindMode);
        } else if (params.startTick !== undefined) {
            // Position at a specific tick
            try {
                cursor.rewindToTick(params.startTick);
            } catch (e) {
                console.log("rewindToTick failed, using manual rewind: " + e.toString());
                cursor.rewind(0); // Start of score
                while (cursor.tick < params.startTick && cursor.next()) {
                    // Advance until we reach the tick or the end
                }
            }
        } else if (params.measure !== undefined) {
            // Rewind to specific measure
            try {
                // First try using rewindToMeasure if it exists
                if (typeof cursor.rewindToMeasure === "function") {
                    cursor.rewindToMeasure(params.measure);
                } else {
                    // Fall back to manual navigation
                    cursor.rewind(0); // Start of score
                    var currentMeasure = 0;
                    
                    // Navigate to the target measure
                    while (currentMeasure < params.measure) {
                        if (!cursor.nextMeasure()) {
                            break; // End of score reached
                        }
                        currentMeasure++;
                    }
                    
                    // Position within the measure if specified
                    if (params.position !== undefined) {
                        for (var i = 0; i < params.position; i++) {
                            if (!cursor.next()) {
                                break; // End of measure reached
                            }
                        }
                    }
                }
            } catch (e) {
                throw new Error("Failed to position cursor to measure: " + e.toString());
            }
        } else {
            // Default to start of score if no position specified
            cursor.rewind(0);
        }
        
        // Set note duration for any notes to be added
        if (params.duration) {
            var z = params.duration.numerator || 1;
            var n = params.duration.denominator || 4;
            cursor.setDuration(z, n);
        } else if (params.numerator !== undefined && params.denominator !== undefined) {
            cursor.setDuration(params.numerator, params.denominator);
        }
        
        return cursor;
    }

    // Initialize cursor state - call this when a score is loaded or created
    function initCursorState() {
        if (!curScore) return;
        
        try {
            curScore.startCmd();
            var cursor = curScore.newCursor();
            cursor.rewind(0); // Start at beginning

            var startTick = cursor.tick;
            cursor.next();
            var endTick = cursor.tick;
            var element = cursor.element;
            var processedElement = processElement(element);

            selectionState = {
                startStaff: cursor.staffIdx,
                endStaff: cursor.staffIdx,
                startTick: startTick,
                elements: [processedElement]
            };
            
            // Clear any selection and set initial selection
            curScore.selection.clear();
            var args = [startTick, endTick, 0, 0];
            var success = curScore.selection.selectRange(...args);
            curScore.endCmd();
            
            return (`${args[0]},${args[1]},${args[2]},${args[3]}`);

        } catch (e) {
            curScore.endCmd(true);
            return ("Error initializing cursor state: " + e.toString());
        }
    }


    // Cursor Navigation and Information

    function selectCurrentMeasure() {
        if (!curScore) return { error: "No score open" };

        try {
            curScore.startCmd();

            // get cursor
            var cursor = createCursor();

            // capture current position
            var currTick = cursor.tick;
            var currStaff = cursor.staffIdx;

            // get score summary

            var scoreSummary = getScoreSummary();

            // figure out which measure the selection is in
            var measureIdx = scoreSummary.measures.filter(measure => measure.startTick <= currTick).length - 1;
            var measureStartTick = scoreSummary.measures[measureIdx].startTick;
            var measureElements = scoreSummary.measures[measureIdx].elements;

            var totalDuration = measureElements.reduce((a, b) => a + b.durationTicks, 0);
            var measureEndTick = measureStartTick + totalDuration;

            // select measure
            var args = [measureStartTick, measureEndTick, currStaff, currStaff];
            var success = curScore.selection.selectRange(...args);

            // update selection state
            selectionState = {
                startStaff: currStaff,
                endStaff: currStaff,
                startTick: measureStartTick,
                elements: measureElements,
                totalDuration: totalDuration
            }

            curScore.endCmd();

            return { 
                success: success, 
                message: `Selected measure ${measureIdx + 1}`, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        }
        catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    // insert measure before current measure and select it
    function insertMeasure(params) {
        if (!curScore) return { error: "No score open" };

        try {
            curScore.startCmd();
            cmd("insert-measure");
            curScore.endCmd();

            // sync state to selection
            syncStateToSelection();

            return { 
                success: true, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    function processElement(element) {
        if (!curScore) return { error: "No score open" };

        var name = element.name;
        var processedElement

        if (name == "Note") {
            processedElement = {
                name: element.name,
                subtype: element.subtype,
                subtypeName: element.subtypeName,
                tempo: element.tempo,
                timesig: element.timesig,
                baseDuration: getDurationName(element.durationType.type),
                dotted: element.durationType.dots,
                durationTicks: element.actualDuration.ticks,
                harmonyType: element.harmonyType,
                accidental: element.accidental,
                accidentalType: element.accidentalType,
                tieBack: element.tieBack,
                tieForward: element.tieForward,
                noteType: element.noteType,
                pitchMidi: element.pitch,
                pitchName: getNoteName(element.pitch),
                tuplet: element.tuplet ? {   
                        durationNumerator: element.tuplet.duration.numerator,
                        durationDenominator: element.tuplet.duration.denominator,
                } : null 
            }
        } 
            
        else if (name == "Rest") {
            processedElement = {
                name: element.name,
                subtype: element.subtype,
                subtypeName: element.subtypeName,
                tempo: element.tempo,
                timesig: element.timesig,
                baseDuration: getDurationName(element.durationType.type),
                dotted: element.durationType.dots,
                durationTicks: element.actualDuration.ticks,
                harmonyType: element.harmonyType,
                tuplet: element.tuplet ? {   
                        durationNumerator: element.tuplet.duration.numerator,
                        durationDenominator: element.tuplet.duration.denominator,
                } : null                    
            }
        }

        else if (name == "Chord") {
            processedElement = {
                name: element.name,
                subtype: element.subtype,
                subtypeName: element.subtypeName,
                tempo: element.tempo,
                timesig: element.timesig,
                baseDuration: getDurationName(element.durationType.type),
                dotted: element.durationType.dots,
                durationTicks: element.actualDuration.ticks,
                noteType: element.noteType,
                notes: Object.keys(element.notes).map(k => ({ pitchMidi: element.notes[k].pitch, pitchName: getNoteName(element.notes[k].pitch)})),
                tuplet: element.tuplet ? {   
                        durationNumerator: element.tuplet.duration.numerator,
                        durationDenominator: element.tuplet.duration.denominator,
                } : null
            }
        }

        else {
            processedElement = Object.keys(element);
        }

        return processedElement;
    }


    // get current selection
    function syncStateToSelection() {
        if (!curScore) return { error: "No score open" };

        try {
            var currSelection = curScore.selection;
            var startSegment = currSelection.startSegment;
            var endSegment = currSelection.endSegment;


            if (startSegment) {
                // we can move to the start of the selection
                var cursor = createCursor({
                    startTick: startSegment.tick});

                var elements = []

                while (cursor.tick < endSegment.tick) {
                    elements.push(cursor.element);
                    if (!cursor.next()) break;
                }

                elements = elements.map(element => processElement(element));

                var totalDuration = elements.reduce((a, b) => a + b.durationTicks, 0);

                selectionState = {
                    startStaff: cursor.staffIdx,
                    endStaff: cursor.staffIdx,
                    startTick: startSegment.tick,
                    elements: elements,
                    totalDuration: totalDuration
                };

                return {
                    success: true, 
                    currentSelection: selectionState
                };
            } else {
                // we can not move to the start of the selection, so just reinit the cursor & selection
                // initCursorState();

                var cursor = createCursor();
                var firstElement = curScore.selection.elements[0];

                curScore.selection.select(firstElement);

                cursor.rewind(1); // rewind to beginning of selection

                var processedElement = processElement(firstElement);
                var duration = processedElement.durationTicks;

                var startTick = cursor.tick;
                var staffIdx = cursor.staffIdx;

                // update selection state
                
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: duration
                };
                
                return {
                    success: false, error: "Could not move to start of selection, reset cursor & selection"
                };
            }
        } catch (e) {
            return { success: false,
                     error: e.toString() 
                };
        }
    }

    
    // Get cursor information
    function getCursorInfo(params) {
        if (!curScore) return { error: "No score open" };
        
        try {        
            // Return the saved state which represents the current selection/cursor
            syncStateToSelection();

            return { 
                success: true, 
                currentSelection: selectionState, 
                currentScore: getScoreSummary()
            };
            
        } catch (e) {
            return { error: e.toString() };
        }
    }
    
    // Set cursor position with unified feedback
    function goToMeasure(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            // check for params
            if (!params.measure) {
                return { error: "Measure parameter must be specified" };
            }

            // Start command for undo
            curScore.startCmd();

            // get relevant measure info
            var score = getScoreSummary();
            var measure = score.measures[params.measure - 1];
            var startTick = measure.startTick;
            
            // Position the cursor
            var cursor = createCursor({ startTick: startTick });
            
            // Update the selection to match cursor position
            var element = cursor.element ? processElement(cursor.element) : null;
            var staffIdx = cursor.staffIdx;
            curScore.selection.clear();
            curScore.selection.selectRange(startTick, startTick + element.durationTicks, staffIdx, staffIdx);
            
            // Save state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                elements: [element],
                totalDuration: element.durationTicks
            };
            
            curScore.endCmd();
            
            return { 
                success: true, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            if (curScore) curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Move to next element with unified feedback
    function nextElement(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            // Start command for undo
            curScore.startCmd();

            // sync state to selection
            syncStateToSelection();

            // if range of elements selected, go to end of range
            var startTick = selectionState.startTick;
            if (selectionState.elements.length > 1) {
                var allButLast = selectionState.elements.slice(0, selectionState.elements.length - 1);
                var duration = allButLast.reduce((a, b) => a + b.durationTicks, 0);
                startTick += duration;
            }
            
            var cursor = createCursor({ startTick: startTick });

            // Move to next element
            var success
            var numElements = params.numElements || 1;
            for (var i = 0; i < numElements; i++) {
                success = cursor.next();
            }
            
            if (success) {
                // Update selection to match new cursor position
                curScore.selection.clear();
                var staffIdx = cursor.staffIdx;
                var startTick = cursor.tick;
                var processedElement = cursor.element ? processElement(cursor.element) : null;
                var duration = processedElement.durationTicks;
                var endTick = startTick + duration;
                var lastTick = curScore.lastSegment.tick

                if (endTick >= lastTick) {
                    // can't select the last element, so need to add a measure at the end
                    cmd("append-measure");
                }

                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);

                // Update saved state
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: duration
                };
                
            }
            
            curScore.endCmd();
            
            if (success) {
                return { 
                    success: true, 
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            } else {
                return { 
                    message: "End of score reached", 
                    success: false, 
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            }
        } catch (e) {
            if (curScore) curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }


    // Move to previous element with unified feedback
    function prevElement(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            // Start command for undo
            curScore.startCmd();

            // sync state to selection
            syncStateToSelection();
            
            var cursor = createCursor();   

            var endTick = cursor.tick;         

            // Move to previous element
            var success

            var numElements = params.numElements || 1;
            for (var i = 0; i < numElements; i++) {
                success = cursor.prev();
            }

            var startTick = cursor.tick;
            
            if (success) {
                // Update selection to match new cursor position
                curScore.selection.clear();
                var staffIdx = cursor.staffIdx;
                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);

                var processedElement = cursor.element ? processElement(cursor.element) : null;
                
                // Update saved state
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: endTick - startTick
                };
            }
            
            curScore.endCmd();
            
            if (success) {
                return { 
                    success: true, 
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            } else {
                return { 
                    message: "Beginning of score reached", 
                    success: false, 
                    currentSelection: selectionState, 
                    currentScore: getScoreSummary()
                };
            }
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Note and Measure Operations
    
    // Add note at cursor position with unified feedback
    function addNote(params) {
        if (!curScore) {
            return { error: "No score open" };
        }

        if (!params.pitch || !params.duration || !params.duration.numerator || !params.duration.denominator || !Object.keys(params).includes("advanceCursorAfterAction")) {
            return { error: "Pitch and duration must be specified. Pitch must be specified as a midi pitch value. Duration must be specified as { numerator: int, denominator: int }. advanceCursorAfterAction must be true or false" };
        }

        // Start command for undo
        curScore.startCmd();
        
        try {
            // sync state to selection
            syncStateToSelection();

            // Create cursor  
            var cursor = createCursor();

            cursor.setDuration(params.duration.numerator, params.duration.denominator);
            
            // Add the note
            if (params.pitch !== undefined) {

                // if there is a rest in the current position, don't use addToChord = true
                var thisIsARest = selectionState.elements.length > 0 && selectionState.elements.filter(element=>element.name=="Rest").length > 0;

                if (thisIsARest == true) {
                    cursor.addNote(params.pitch, false);
                } else {
                    cursor.addNote(params.pitch, true);
                }

                // reselect the currently relevant segment
                cursor.rewindToTick(selectionState.startTick);

                if (params.advanceCursorAfterAction == true) {
                    cursor.next();
                }

                var element = cursor.element;
                var processedElement = processElement(element);
                var duration = processedElement.durationTicks;
                var startTick = cursor.tick;
                var endTick = startTick + duration;

                var staffIdx = cursor.staffIdx;

                // Update selection state
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx,
                    startTick: startTick,
                    elements: [processedElement],
                    totalDuration: duration
                }

                curScore.selection.clear();
                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);
                
                curScore.endCmd();
                return { 
                    success: true, 
                    message: "Note added with pitch " + params.pitch + " at tick " + cursor.tick,
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            } else {
                curScore.endCmd(true); // Rollback
                return { error: "Pitch must be specified as a midi pitch value" };
            }
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }


    // Add a rest at cursor position
    function addRest(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.duration || !params.duration.numerator || !params.duration.denominator || !Object.keys(params).includes("advanceCursorAfterAction")) {
            return { error: "Duration must be specified as { numerator: int, denominator: int }. advanceCursorAfterAction must be true or false" };
        }

        // Start command for undo
        curScore.startCmd();
        
        try {
            // sync state to selection
            syncStateToSelection();
            
            var cursor = createCursor();

            // Add the rest
            cursor.setDuration(params.duration.numerator, params.duration.denominator)

            cursor.addRest();

            cursor.rewindToTick(selectionState.startTick);

            if (params.advanceCursorAfterAction == true) {
                cursor.next();
            }

            // reselect the currently relevant segment
            var startTick = cursor.tick;

            var element = cursor.element;
            var processedElement = processElement(element);
            var duration = processedElement.durationTicks;
            var endTick = cursor.tick + duration;
            var staffIdx = cursor.staffIdx;

            // Update selection state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                elements: [processedElement],
                totalDuration: duration
            }

            // Update selection to match cursor position
            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);

            curScore.endCmd();
            return { 
                success: true, 
                message: "Rest added", 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Add a tuplet
    function addTuplet(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.ratio || !params.duration || !params.duration.numerator || !params.duration.denominator || !params.ratio.numerator || !params.ratio.denominator || !Object.keys(params).includes("advanceCursorAfterAction")) {
            return { error: "Ratio and duration must be specified in the form { numerator: int, denominator: int }. advanceCursorAfterAction must be true or false" };
        }
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var cursor = createCursor();

            cursor.setDuration(params.duration.numerator, params.duration.denominator);
            
            // Create ratio fraction
            var ratio = fraction(params.ratio.numerator, params.ratio.denominator);
            
            // Create duration fraction
            var duration = fraction(params.duration.numerator, params.duration.denominator);
            
            // Add the tuplet
            cursor.addTuplet(ratio, duration);

            // reselect the currently relevant segment

            cursor.next();

            if (params.advanceCursorAfterAction == true) {
                cursor.next();
            }

            var endTick = cursor.tick;
            cursor.prev();
            var startTick = cursor.tick;
            var staffIdx = cursor.staffIdx;

            // Update selection state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                elements: [processElement(cursor.element)],
                totalDuration: cursor.element.durationTicks
            }

            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);
        
            curScore.endCmd();

            return { 
                success: true, 
                message: "Tuplet " + params.ratio.numerator + ":" + 
                        params.ratio.denominator + " added",
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Go to the beginning of the last measure
    function goToFinalMeasure(params) {
        if (!curScore) return { error: "No score open" };

        // Start command for undo
        curScore.startCmd();

        var cursor = createCursor({ startTick: 0 });
        var count = 0;
        var startTick;


        try {

            while (cursor.nextMeasure()) {
                startTick = cursor.tick;
                count++;
            }

            // if already at the end, do nothing
            if (count == 0) {
                return { 
                    success: false, 
                    message: "Already at the last measure",
                    currentSelection: selectionState,
                    currentScore: getScoreSummary()
                };
            }

            // Update the selection and state
            curScore.selection.clear();
            
            // reset cursor
            cursor.rewindToTick(startTick);
            var success = cursor.next();
            var endTick = cursor.tick;

            var staffIdx = cursor.staffIdx;
            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx);
            
            // Update saved state
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx,
                startTick: startTick,
                endTick: endTick,
                element: cursor.element ? cursor.element.name : null
            };

            curScore.endCmd();

            return { 
                success: true, 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }

    }

    // Add measures to the score
    function appendMeasure(params) {
        if (!curScore) return { error: "No score open" };
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var count = params.count || 1;
            
            for (var i = 0; i < count; i++) {
                cmd("append-measure");
            }
            
            curScore.endCmd();
            return { 
                success: true, 
                message: count + " measure(s) appended", 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Delete current selection
    function deleteSelection(params) {
        if (!curScore) return { error: "No score open" };
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var cursor = createCursor({
                measure: params.measure
            });
            
            cmd("delete");
            
            curScore.endCmd();

            return { 
                success: true, 
                message: "Selection deleted", 
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Staff and Instrument Operations
    
    // Add a new staff/instrument
    function addInstrument(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.instrumentId) {
            return { error: "Instrument ID must be specified" };
        }
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            // Add the part with the specified instrument
            curScore.appendPart(params.instrumentId);
            
            curScore.endCmd();
            return { 
                success: true, 
                message: "Instrument " + params.instrumentId + " added" 
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Mute/unmute a staff - TBD
    function setStaffMute(params) {
        if (!curScore) return { error: "No score open" };
        
        if (params.staff === undefined) return { error: "No staff specified" };
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var staff;
            
            // Get staff through staves array or staff method
            if (curScore.staves && curScore.staves.length > params.staff) {
                staff = curScore.staves[params.staff];
            } else if (typeof curScore.staff === "function") {
                staff = curScore.staff(params.staff);
            }
            
            if (staff) {
                staff.invisible = params.mute ? true : false;
                curScore.endCmd();
                return { 
                    success: true, 
                    message: "Staff " + (params.mute ? "muted" : "unmuted") 
                };
            } else {
                curScore.endCmd(true); // Rollback
                return { error: "Staff not found" };
            }
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Change instrument sound - TBD
    function setInstrumentSound(params) {
        if (!curScore) return { error: "No score open" };
        
        if (params.staff === undefined) return { error: "No staff specified" };
        if (!params.instrumentId) return { error: "No instrument ID specified" };
        
        // This is a placeholder - implementation depends on MuseScore 4's API
        // Start command for undo
        curScore.startCmd();
        
        try {
            // Try to trigger instrument change through command
            cmd("instruments");
            
            curScore.endCmd();
            return { 
                success: true, 
                message: "Instrument dialog opened, manual selection required" 
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Time Signature
    
    // Set time signature
    function setTimeSignature(params) {
        if (!curScore) return { error: "No score open" };
        
        if (!params.numerator || !params.denominator) {
            return { error: "Both numerator and denominator must be specified" };
        }
        
        // Start command for undo
        curScore.startCmd();
        
        try {
            var cursor = createCursor();
            var currTick = cursor.tick;
            var currElement = processElement(cursor.element);
            var currStaff = cursor.staffIdx;

            var ts = newElement(Element.TIMESIG)
            ts.timesig = fraction(params.numerator, params.denominator);
            cursor.add(ts)

            // reset selection to previously selected element
            curScore.selection.selectRange(currTick, currTick + currElement.durationTicks, currStaff, currStaff);
            
            curScore.endCmd();
            return { 
                success: true, 
                message: "Time signature set to " + params.numerator + "/" + params.denominator + " for this measure until the next measure with a specified time signature",
                currentSelection: selectionState,
                currentScore: getScoreSummary()
            };
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }
    
    // Score Information + Helper Functions
    
    // Get note names
    function getNoteName(note) {
        const noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        var noteName = noteNames[note % 12];
        return noteName;
    }

    function getDurationName(duration) {
        const durationNames = ["LONG","BREVE","WHOLE","HALF","QUARTER","EIGHTH","16TH","32ND","64TH","128TH","256TH","512TH","1024TH","ZERO","MEASURE","INVALID"];

        var durationName = durationNames[duration];
        return durationName;
    }

    function getScoreSummary() {
        if (!curScore) return { error: "No score open" };

         try {
            var score = {
                numMeasures: curScore.nmeasures,
                measures: [],
                staves: []
            };
            
            // Analyze each staff
            for (var i = 0; i < curScore.nstaves; i++) {
                var staff;
                
                // Get staff through staves array or staff method
                if (curScore.staves && curScore.staves.length > i) {
                    staff = curScore.staves[i];
                } else if (typeof curScore.staff === "function") {
                    staff = curScore.staff(i);
                }
                
                if (staff) {
                    score.staves.push({
                        name: staff.name || ("Staff " + (i + 1)),
                        shortName: staff.shortName,
                        visible: !staff.invisible
                    });
                } else {
                    score.staves.push({
                        name: "Staff " + (i + 1)
                    });
                }
            }

            // Analyze each measure
            curScore.startCmd();

            // Initialize cursor
            var cursor = createCursor({startTick: 0});

            // first, just capture the measures and their boundaries

            var measureBoundaries = [];

            for (var i = 0; i < curScore.nmeasures; i++) {
                // create measure
                var measure = {
                    measure: i+1, 
                    startTick: 0,
                    numElements: 0, 
                    elements: []
                };

                // track measure boundaries
                measure.startTick = cursor.tick;
                measureBoundaries.push(cursor.tick);

                // add measure to score
                score.measures.push(measure);

                // set cursor to start of next measure
                cursor.nextMeasure();
            }

            // now, reset the cursor and process each element

            cursor.rewindToTick(0);

            while (true) {
                var staffIdx = cursor.staffIdx;
                var element = cursor.element;
            
                // figure out which measure the element is in
                var measureIdx = measureBoundaries.filter(tick => tick <= cursor.tick).length - 1;

                // process element, add to measure and increment count
                score.measures[measureIdx].numElements++;

                var processedElement = processElement(element);

                processedElement.startTick = cursor.tick;

                if (processedElement) {
                    score.measures[measureIdx].elements.push(processedElement);
                }

                if (!cursor.next()) break;
            }
            
            // Reset cursor state
            // initCursorState();
            cursor.rewindToTick(selectionState.startTick);
            curScore.selection.select(cursor.element);
    

            curScore.endCmd();

            return score;
        } catch (e) {
            curScore.endCmd(true); // Rollback on error
            return { error: e.toString() };
        }
    }

    // Get more detailed score structure
    function getScore(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            var analysis = getScoreSummary()
            return { success: true, analysis: analysis };
        } catch (e) {
            return { error: e.toString() };
        }
    }


    // Init
    onRun: {
        console.log("Starting MuseScore API Server on port 8765");
        
        // Start the WebSocket server
        api.websocketserver.listen(8765, function(clientId) {
            console.log("Client connected with ID: " + clientId);
            clientConnections.push(clientId);
            
            // Set up message handler for this client
            api.websocketserver.onMessage(clientId, function(message) {
                processMessage(message, clientId);
            });
        });
    
        // Initialize cursor state for any open score

        if (curScore) {
            initCursorState();
        }

    }
}
