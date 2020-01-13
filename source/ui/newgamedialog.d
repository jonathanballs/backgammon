module ui.newgamedialog;

import std.string;
import std.stdio;
import std.variant;

import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Dialog;
import gtk.Entry;
import gtk.Frame;
import gtk.Label;
import gtk.ListStore;
import gtk.Notebook;
import gtk.TreeIter;
import gtk.Widget;
import gtk.Window;

import player;
import ai.gnubg;

enum formPadding = 10;

// Helper function for configuring widgets
private void setMarginsExpand(Widget w,
        uint top, uint bottom, uint left, uint right,
        bool vExpand, bool hExpand) {
    w.setMarginTop(top);
    w.setMarginBottom(bottom);
    w.setMarginLeft(left);
    w.setMarginRight(right);
    w.setVexpand(vExpand);
    w.setHexpand(hExpand);
}

class NewGameDialog : Dialog {
    Notebook tabs;

    /**
     * Human vs AI
     */
    Box hvaBox;
    HumanSelector hvaHumanSelector;
    AISelector hvaAISelector;
    Button hvaStartGame;

    /**
     * Human vs Human
     */
    Box hvhBox;
    HumanSelector hvhHumanSelector1;
    HumanSelector hvhHumanSelector2;
    Button hvhStartGame;

    /**
     * AI vs AI
     */
    Box avaBox;
    AISelector avaAISelector1;
    AISelector avaAISelector2;
    Button avaStartGame;
    
    Player[] availableAIs;

    this (Window parent) {
        super();
        /**
         * Set position
         */
        this.setTransientFor(parent);
        this.setPosition(GtkWindowPosition.CENTER_ON_PARENT);
        this.setTypeHint(GdkWindowTypeHint.DIALOG);
        this.setModal(true);
        this.setSizeRequest(400, 475);
        this.setTitle("New Game");

        availableAIs = getAvailableAIs();

        /**
         * Human vs AI
         */
        hvaBox = new Box(GtkOrientation.VERTICAL, formPadding);
        hvaBox.setMarginsExpand(formPadding, formPadding, formPadding, formPadding, true, true);
        hvaAISelector = new AISelector(availableAIs, "Artificial Intelligence");
        hvaHumanSelector = new HumanSelector("Human", getLocalUserName());
        hvaBox.packStart(hvaAISelector, false, false, 0);
        hvaBox.packStart(hvaHumanSelector, false, false, 0);
        hvaStartGame = new Button("Start Game");
        hvaStartGame.getStyleContext().addClass("suggested-action");
        hvaStartGame.addOnClicked((Button b) {
            auto ai = hvaAISelector.getActiveSelection();
            auto human = hvaHumanSelector.getActiveSelection();
            writeln([ai, human]);
        });
        hvaBox.packEnd(hvaStartGame, false, false, 0);

        /**
         * AI vs AI
         */
        avaBox = new Box(GtkOrientation.VERTICAL, formPadding);
        avaBox.setMarginsExpand(formPadding, formPadding, formPadding, formPadding, true, true);
        avaAISelector1 = new AISelector(availableAIs, "Artificial Intelligence 1");
        avaAISelector2 = new AISelector(availableAIs, "Artificial Intelligence 2");
        avaBox.packStart(avaAISelector1, false, false, 0);
        avaBox.packStart(avaAISelector2, false, false, 0);
        avaStartGame = new Button("Start Game");
        avaStartGame.getStyleContext().addClass("suggested-action");
        avaStartGame.addOnClicked((Button b) {
            auto ai1 = avaAISelector1.getActiveSelection();
            auto ai2 = avaAISelector2.getActiveSelection();
            writeln([ai1, ai2]);
        });
        avaBox.packEnd(avaStartGame, false, false, 0);

        /**
         * Human vs Human
         */
        hvhBox = new Box(GtkOrientation.VERTICAL, formPadding);
        hvhBox.setMarginsExpand(formPadding, formPadding, formPadding, formPadding, true, true);
        hvhHumanSelector1 = new HumanSelector("Human", getLocalUserName());
        hvhHumanSelector2 = new HumanSelector("Human", getLocalUserName());
        hvhBox.packStart(hvhHumanSelector1, false, false, 0);
        hvhBox.packStart(hvhHumanSelector2, false, false, 0);
        hvhStartGame = new Button("Start Game");
        hvhStartGame.getStyleContext().addClass("suggested-action");
        hvhStartGame.addOnClicked((Button b) {
            auto human1 = hvhHumanSelector1.getActiveSelection();
            auto human2 = hvhHumanSelector2.getActiveSelection();
            writeln([human1, human2]);
        });
        hvhBox.packEnd(hvhStartGame, false, false, 0);

        tabs = new Notebook();
        tabs.appendPage(hvaBox, new Label("Human vs AI"));
        tabs.appendPage(hvhBox, new Label("Human vs Human"));
        tabs.appendPage(avaBox, new Label("AI vs AI"));

        this.getContentArea().add(tabs);

        this.showAll();
    }

    private Player[] getAvailableAIs() {
        Player[] ais = [
            // Player("Default", "local", PlayerType.AI),
        ];

        // Gnu Backgammon
        import std.process : execute;
        try {
            const auto gnubg = execute(["gnubg", "--version"]);
            if (!gnubg.status) {
                auto lines = gnubg.output.split('\n');
                if (lines.length) {
                    ais ~= Player(lines[0], "gnubg", PlayerType.AI);
                }
            }
        } catch (Exception e) {
            // Gnu Backgammon is not installed
        }

        return ais;
    }

    /**
     * Get the local user name. Useful as  a default for player name
     */
    private string getLocalUserName() {
        import std.process : environment;
        version(Posix) {
            return environment.get("USER", "Human");
        }
        version(Windows) {
            return environment.get("%USERNAME%", "Human");
        }
    }
}

private class AISelector : Box {
    Label label;
    ComboBoxText aiSelector;
    Box aiSettings;
    Player[] availableAIs;

    Variant aiConfig;

    this(Player[] _availableAIs, string labelString) {
        super(GtkOrientation.VERTICAL, formPadding);
        this.setMarginLeft(formPadding);
        this.setMarginRight(formPadding);
        this.setMarginTop(formPadding);
        this.setMarginBottom(formPadding);

        label = new Label(labelString);
        this.packStart(label, false, false, 0);

        availableAIs = _availableAIs;

        aiSelector = new ComboBoxText(false);
        foreach (i, Player ai; availableAIs) {
            aiSelector.append(ai.id, ai.name);
        }

        aiSelector.addOnChanged((ComboBoxText combo) {
            auto setting = combo.getActiveId();
            if (aiSettings) aiSettings.destroy();

            switch (setting) {
            case "gnubg":
                aiSettings = gnubgAISettings();
                break;
            default:
                break;
            }

            if (aiSettings) {
                aiSettings.showAll();
                this.packEnd(aiSettings, false, false, 0);
            }
        });

        this.packStart(aiSelector, false, false, 0);
        if (availableAIs.length) {
            aiSelector.setActive(0);
        } else {
            aiSelector.append("none", "No AIs installed...");
            aiSelector.setActive(0);
            aiSelector.setSensitive(false);
        }
    }

    /**
     * Return the currently active selection
     */
    Player getActiveSelection() {
        auto selection = aiSelector.getActiveId;
        switch (selection) {
        case "gnubg": 
            return Player(
                "Gnubg " ~ aiConfig.peek!(GnubgEvalContext).name,
                "gnubg",
                PlayerType.AI,
                aiConfig);
        case "none":
        default:
            throw new Exception("Error: No AI selected.");
        }
    }

    /**
     * Create configuration form for gnubg
     */
    private Box gnubgAISettings() {
        Box box = new Box(Orientation.VERTICAL, 0);

        auto difficultySelection = new ComboBoxText(false);
        foreach (context; gnubgDefaultEvalContexts) {
            difficultySelection.append(context.name, context.name);
        }
        difficultySelection.addOnChanged((ComboBoxText combo) {
            aiConfig = gnubgDefaultEvalContexts[combo.getActive()];
        });
        difficultySelection.setActive(2); // Intermediate
        box.add(difficultySelection);

        return box;
    }
}

private class HumanSelector : Box {
    Label label;
    Label nameLabel;
    Entry nameEntry;

    /**
     * Create a new Human Selector
     */
    this(string _label, string defaultName) {
        super(GtkOrientation.VERTICAL, formPadding);
        this.setMarginLeft(formPadding);
        this.setMarginRight(formPadding);
        this.setMarginTop(formPadding);
        this.setMarginBottom(formPadding);

        label = new Label(_label);
        this.packStart(label, false, false, 0);

        nameLabel = new Label("Name:");
        nameEntry = new Entry(defaultName);
        Box box = new Box(GtkOrientation.HORIZONTAL, formPadding);
        box.packStart(nameLabel, false, false, 0);
        box.packStart(nameEntry, true, true, 0);
        this.packStart(box, false, false, 0);
    }

    Player getActiveSelection() {
        return Player(nameEntry.getText(), nameEntry.getText(), PlayerType.User);
    }
}
