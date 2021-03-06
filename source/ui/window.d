module ui.window;

import std.concurrency;
import std.parallelism;
import std.stdio;
import std.variant;
import core.thread;

import gdk.FrameClock;
import gdk.Keysyms;
import gio.ThemedIcon;
import gtk.Box;
import gtk.Button;
import gtk.Container;
import gtk.Dialog;
import gtk.HeaderBar;
import gtk.Image;
import gtk.Label;
import gtk.Main;
import gtk.MainWindow;
import gtk.MessageDialog;
import gtk.Revealer;
import gtk.Widget;

import ai.gnubg;
import gameplay.gamestate;
import gameplay.match;
import gameplay.player;
import networking.fibs.controller;
import networking.messages;
import networking;
import ui.board.boardwidget;
import ui.fibssidebar;
import ui.matchoverviewbox;
import ui.networkgamedialog;
import ui.newgamedialog;
import utils.addtickcallback;

/**
 * The MainWindow of the backgammon game. Also acts as a high level controller
 * for receiving button presses, network events etc.
 */
class BackgammonWindow : MainWindow {
    private:

    // Header bar
    HeaderBar header;
    Button newGameBtn;
    Button inetGameBtn;
    Button finishTurnBtn;
    Button undoMoveBtn;

    // Dialogs
    NewGameDialog newGameDialog;
    NetworkGameDialog networkWidget;

    // Main window contents
    Box gameplayBox;
    Box contentBox;

    // Fibs sidebar
    FIBSSidebar fibsSidebar;
    public Revealer fibsSidebarRevealer;
    public BackgammonBoardWidget backgammonBoard;

    // Match sidebar
    MatchOverviewBox matchOverviewBox;

    BackgammonMatch match;

    Task!(gnubgGetTurn, GameState, GnubgEvalContext) *aiGetTurn;
    Turn remoteResult;

    FIBSController fibsController;

    /**
     * Create a new backgammon board window
     */
    public this() {
        super("Backgammony");
        this.setDefaultSize(1000, 600);
        this.addOnKeyPress(&onKeyPress);
        this.addTickCallback(&handleThreadMessages);
        this.addOnDestroy(&onDestroy);

        // Header
        header = new HeaderBar();
        header.setTitle("Backgammony");
        header.setShowCloseButton(true);
        this.setTitlebar(header);

        // New game
        newGameBtn = new Button("New Game");
        newGameBtn.addOnClicked((Button b) => openNewGameDialog() );
        header.packStart(newGameBtn);

        // Internet game
        inetGameBtn = new Button();
        auto icon = new ThemedIcon("network-server-symbolic");
        auto inetImg = new Image();
        inetImg.setFromGicon(icon, IconSize.BUTTON);
        inetGameBtn.add(inetImg);
        inetGameBtn.addOnClicked((Button b) => openNewNetworkGameDialog() );
        header.packStart(inetGameBtn);

        // Undo and finish buttons
        undoMoveBtn = new Button();
        icon = new ThemedIcon("edit-undo-symbolic");
        inetImg = new Image();
        inetImg.setFromGicon(icon, IconSize.BUTTON);
        undoMoveBtn.add(inetImg);
        undoMoveBtn.addOnClicked((Button b) {
            backgammonBoard.undoSelectedMove();
        });
        undoMoveBtn.setSensitive(false);

        finishTurnBtn = new Button("Finish");
        finishTurnBtn.addOnClicked((Button b) {
            /**
             * Is this a network game? Should this be on a signal listener?
             */
            if (match.isNetworkGame) {
                auto netThread = match.oppositeTurn().config.peek!Tid;
                auto moves = backgammonBoard.getSelectedMoves();
                auto msg = NetworkThreadNewMove(cast(uint) moves.length);
                foreach (i, PipMovement m; moves) {
                    msg.moves[i] = m;
                }
                send(*netThread, msg);
            }
            match.gs.applyTurn(backgammonBoard.getSelectedMoves());
        });
        finishTurnBtn.setSensitive(false);
        header.packEnd(finishTurnBtn);
        header.packEnd(undoMoveBtn);

        // Game board
        backgammonBoard = new BackgammonBoardWidget();
        backgammonBoard.onChangePotentialMovements.connect(() {
            undoMoveBtn.setSensitive(false);
            finishTurnBtn.setSensitive(false);

            if (match.currentTurn().type == PlayerType.User) {

                undoMoveBtn.setSensitive(!!backgammonBoard.getSelectedMoves().length);
                if (match.gs.turnState == TurnState.MoveSelection) {
                    try {
                        backgammonBoard.getGameState().validateTurn(backgammonBoard.getSelectedMoves());
                        finishTurnBtn.setSensitive(true);
                    } catch (Exception e) {
                        finishTurnBtn.setSensitive(false);
                    }
                }
            }
        });
        backgammonBoard.onCompleteDiceAnimation.connect(() {
            // If it's a network player then we await their movement
            // TODO: Perhaps this should be triggered when a user finishes and
            // can't move...
            if (match.currentTurn().type == PlayerType.User) {
                if (match.gs.turnState == TurnState.MoveSelection
                        && match.gs.generatePossibleTurns().length == 0) {
                    backgammonBoard.finishTurn();
                }
            }
        });

        // FIBS sidebar
        fibsSidebar = new FIBSSidebar();
        fibsSidebarRevealer = new Revealer();
        fibsSidebarRevealer.setTransitionType(GtkRevealerTransitionType.SLIDE_LEFT);
        fibsSidebarRevealer.add(fibsSidebar);
        fibsSidebarRevealer.setRevealChild(false);

        // Match sidebar
        matchOverviewBox = new MatchOverviewBox();

        // Layout
        contentBox = new Box(GtkOrientation.HORIZONTAL, 0);
        gameplayBox = new Box(GtkOrientation.VERTICAL, 0);
        gameplayBox.packStart(matchOverviewBox, false, true, 0);
        gameplayBox.packStart(backgammonBoard, true, true, 0);
        contentBox.packStart(gameplayBox, true, true, 0);
        contentBox.packStart(fibsSidebarRevealer, false, true, 0);
        this.add(contentBox);
    }

    /**
     * Keyboard Shortcuts
     */
    bool onKeyPress(GdkEventKey* g, Widget w) {
        // If CTRL key pressed
        if (g.state & ModifierType.CONTROL_MASK) {
            switch(g.keyval) {
            case Keysyms.GDK_n:
                this.openNewGameDialog();
                break;
            case Keysyms.GDK_i:
                this.openNewNetworkGameDialog();
                break;
            case Keysyms.GDK_f:
                this.backgammonBoard.toggleFPSCounter();
                break;
            default: break;
            }
        }

        return false;
    }

    /**
     * Open the new game dialog
     */
    void openNewGameDialog() {
        // Create new game
        newGameDialog = new NewGameDialog(this);
        newGameDialog.onCreateNewGame.connect((GameState gs) {
            setGameState(gs);
            gs.newGame();
            newGameDialog.destroy();
            newGameDialog = null;
        });
    }

    /**
     * Open the new network game dialog
     */
    void openNewNetworkGameDialog() {
        networkWidget = new NetworkGameDialog(this);
        networkWidget.onCreateNewGame.connect((GameState gs) {
            networkWidget.destroy();
            networkWidget = null;
            setGameState(gs);
            gs.newGame();
        });
        networkWidget.onFibsConnection.connect((FIBSController newController) {
            networkWidget.destroy();
            networkWidget = null;
            this.setFibsController(newController);
            this.fibsSidebarRevealer.setRevealChild(true);
        });
    }

    public void setGameState(GameState gs) {
        this.aiGetTurn = null;
        auto _match = new BackgammonMatch(gs.players[Player.P1], gs.players[Player.P2]);
        _match.gs = gs;
        setBackgammonMatch(_match);
    }

    public void setBackgammonMatch(BackgammonMatch m) {
        this.match = m;

        // Update the backgammon board
        backgammonBoard.setGameState(match.gs);
        if (match.player1.type == PlayerType.User) {
            backgammonBoard.setPlayerCorner(Player.P1, Corner.BR);
        } else {
            backgammonBoard.setPlayerCorner(Player.P2, Corner.BR);
        }

        // Update match overview box
        this.matchOverviewBox.setMatch(this.match);

        // Update 
        if (this.match && this.match.gs) {
            this.match.gs.onDiceRolled.disconnect(&this.onGameStateDiceRolled);
            this.match.gs.onBeginTurn.disconnect(&this.onGameStateBeginTurn);
            this.match.gs.onEndGame.disconnect(&this.onGameStateEndGame);
        }
        this.match.gs.onDiceRolled.connect(&this.onGameStateDiceRolled);
        this.match.gs.onBeginTurn.connect(&this.onGameStateBeginTurn);
        this.match.gs.onEndGame.connect(&this.onGameStateEndGame);
    }

    // Link up gamestate to various things
    // How are dice rolls handled?
    // TODO: This shouldn't be here at all. Move this kind of thing away!!
    void onGameStateBeginTurn(GameState _gs, Player p) {
        header.setSubtitle(p == Player.P1 ? "Black to play" : "White to play");
        finishTurnBtn.setSensitive(false);

        if (match && match.player1.type == PlayerType.FIBS) {
            return;
        }

        auto pm = p == Player.P1 ? match.player1 : match.player2;

        // Local games we can just roll the dice automatically. Otherwise,
        // we will wait for a dice roll from the network thread.
        if (match && !match.isNetworkGame) {
            if (_gs.equals(_gs.dup.newGame())) {
                backgammonBoard.displayMessage(pm.name ~ " starts", () {
                    _gs.rollDice();
                });
            } else {
                _gs.rollDice();
            }
        } else {
            if (pm.type == PlayerType.User) {
                auto netThread = match.oppositeTurn().config.peek!Tid;
                send(*netThread, NetworkTurnDiceRoll());
            }
        }
    }

    void onGameStateDiceRolled(GameState gs, uint die1, uint die2) {
        if (match.currentTurn().type == PlayerType.User) {
            if (!gs.generatePossibleTurns.length) {
                finishTurnBtn.setSensitive(true);
            }
        }

        // Start an AI request if necessary
        if (match.currentTurn().type == PlayerType.AI) {
            GnubgEvalContext context = *match.currentTurn().config.peek!GnubgEvalContext;
            aiGetTurn = task!gnubgGetTurn(gs, context);
            aiGetTurn.executeInNewThread();
        }
    }

    void onGameStateEndGame(GameState gs, Player winner) {
        finishTurnBtn.setSensitive(false);
        undoMoveBtn.setSensitive(false);
    }

    public void setFibsController(FIBSController fibsController) {
        if (this.fibsController) {
            if (this.fibsController.connectionStatus.status == FIBSConnectionStatus.Connected) {
                writeln("Warning, setting a new FIBS connection while already connected");
                this.fibsController.disconnect();
            }
        }
        this.fibsController = fibsController;
        this.fibsSidebar.setController(fibsController);
        this.fibsSidebarRevealer.setRevealChild(true);
        this.fibsController.onUpdateMatchState.connect(&setBackgammonMatch);
    }

    bool handleThreadMessages(Widget w, FrameClock f) {
        if (fibsController) {
            fibsController.processMessages();
        }

        try {
            if (aiGetTurn && aiGetTurn.done) {
                remoteResult = aiGetTurn.yieldForce;
                aiGetTurn = null;
                this.match.gs.applyTurn(remoteResult);
            }
        } catch (Exception e) {
            aiGetTurn = null;
            auto dialog = new MessageDialog(this,
                GtkDialogFlags.DESTROY_WITH_PARENT | GtkDialogFlags.MODAL,
                GtkMessageType.ERROR,
                GtkButtonsType.OK,
                "%s",
                e.message.idup);
            dialog.showAll();
            dialog.addOnResponse((int i, Dialog d) => dialog.destroy());
        }

        if (match && match.isNetworkGame && match.player1.type != PlayerType.FIBS) {
            receiveTimeout(0.msecs,
                (NetworkThreadNewMove moves) {
                    assert(match.gs.turnState == TurnState.MoveSelection);
                    foreach(move; moves.moves[0..moves.numMoves]) {
                        backgammonBoard.selectMove(move);
                    }
                    backgammonBoard.finishTurn();
                },
                (NetworkNewDiceRoll diceRoll) {
                    writeln("Received dice roll: ", diceRoll);
                    this.backgammonBoard.getGameState.rollDice(diceRoll.dice1, diceRoll.dice2);
                },
                (NetworkThreadUnhandledException e) {
                    auto dialog = new MessageDialog(this,
                        GtkDialogFlags.DESTROY_WITH_PARENT | GtkDialogFlags.MODAL,
                        GtkMessageType.ERROR,
                        GtkButtonsType.OK,
                        "%s",
                        e.message);
                    dialog.showAll();
                    dialog.addOnResponse((int i, Dialog d) => dialog.destroy());
                }
            );
        }
        return true;
    }

    void onDestroy(Widget w) {
        if (this.fibsController) {
            fibsController.disconnect();
        }
    }

    public mixin AddTickCallback;
}
