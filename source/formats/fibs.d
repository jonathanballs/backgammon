module formats.fibs;

import std.format;
import std.conv;
import std.algorithm;
import std.array;
import game;

/**
 * Contains functions and methods for handling FIBS encoded games and moves
 * Reference: http://www.fibs.com/fibs_interface.html#game_play
 * P1 = 0 (positive), P2 = X (negative)
 */

/**
 * Convert a GameState to FIBS string.
 */
string toFibsString(GameState gs, Player perspective = Player.P1) {
    return format!"board:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s"(
        "You:Opponent", // Player names
        "1", // Match length
        "0:0", // Current Match Score
        gs.points.array
            .map!(p => (p.owner == Player.P2 ? "-" : "") ~ p.numPieces.to!string ~ ":")
            .reduce!((a,b) => a ~ b)[0..$-1], // Board
        gs.currentPlayer == Player.P1 ? "1" : "-1", // Turn
        format!"%d:%d:%d:%d"(gs.diceValues[0], gs.diceValues[1], gs.diceValues[0], gs.diceValues[1]), // Dice
        "1", // Doubling cube
        "0", // May double
        "0", // Was doubled
        perspective == Player.P1 ? "1" : "-1", // Color
        perspective == Player.P1 ? "-1" : "1", // Direction (P1 moves downwards)
        perspective == Player.P1 ? "0:25" : "25:0", // Home and bar
        format!"%d:%d"(gs.borneOffPieces[perspective], gs.borneOffPieces[perspective.opposite()]), // On Home
        format!"%d:%d"(gs.takenPieces[perspective], gs.takenPieces[perspective.opposite()]), // On Bar
        "0:0", // Forced Move
        "0"  // Redoubles
    );
}

/**
 * Convert a PipMovement to FIBS string.
 */
string toFibsString(PipMovement pipMovement) {
    switch (pipMovement.moveType) {
    case PipMoveType.Movement:
        return format!"move %d %d"(pipMovement.startPoint, pipMovement.endPoint);
    case PipMoveType.BearingOff:
        return format!"move %d off"(pipMovement.startPoint);
    case PipMoveType.Entering:
        return format!"move bar %d"(pipMovement.endPoint);
    default: assert(0);
    }
}

// PipMovement parseFibsString(string fibsString){
// }

unittest {
    import std.stdio;
    writeln("Testing FIBS formatting");
    auto gs = new GameState();
    gs.newGame();
    gs.toFibsString;

    auto movement = PipMovement(
        PipMoveType.Movement, 5, 7, 2
    );
    assert(movement.toFibsString == "move 5 7");
}
