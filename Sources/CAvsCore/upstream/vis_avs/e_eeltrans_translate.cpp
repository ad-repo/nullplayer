#include "e_eeltrans.h"

#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#define EELTRANS_TMP_PLACEHOLDER_STR "cahghagahS8Jee4"
#define NEWLINE                      "\r\n"

const static std::string VAR_PATTERN =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.";

enum ReplacementMode {
    REPLACE_CASE_SENSITIVE = 0,
    REPLACE_CASE_INSENSITIVE,
    REPLACE_C_STYLE
};

class Replacement {
   public:
    std::string from;
    std::string to;
    ReplacementMode mode;
    Replacement(std::string const& from,
                std::string const& to,
                const ReplacementMode mode)
        : from(from), to(to), mode(mode) {}
    bool operator==(Replacement const& other) const { return this->from == other.from; }
    void c_style_replace(std::string& input);
};

enum TranslateMode { MODE_LINEAR = 0, MODE_ASSIGN, MODE_EXEC, MODE_PLUS };

class Translator {
    TranslateMode mode;
    bool trans_first;
    std::vector<Replacement> replacements;
    const std::string& avs_base_path;

    void do_replacements(std::string& input);
    void command_split(std::vector<std::string>& output, std::string input);
    std::string parse_command(std::string input, int indent);
    std::string transform_code(std::string input, int indent, bool do_parse);
    void handle_comment(std::string const& comment);
    void read_settings_from_comments(std::string& input);
    std::string handle_preprocessor(std::string input);

   public:
    Translator(TranslateMode mode,
               bool translate_firstlevel,
               const std::string& avs_base_path)
        : mode(mode), trans_first(translate_firstlevel), avs_base_path(avs_base_path) {}
    std::string translate(const std::string& prefix_code, std::string input);
};

static void strtolower(std::string& input) {
    for (unsigned int i = 0; i < input.size(); ++i) {
        input[i] = tolower(input[i]);
    }
}

static void join(std::string& output,
                 std::vector<std::string>& input,
                 const std::string& delimiter) {
    switch (input.size()) {
        case 0: output = ""; break;
        default:
            output = input[0];
            for (unsigned int i = 1; i < input.size(); ++i) {
                output += delimiter + input[i];
            }
            break;
    }
}

static void split(std::vector<std::string>& output,
                  std::string input,
                  std::string delimiter,
                  int limit = -1) {
    output.clear();
    if (limit < 0) {
        unsigned int lastpos = 0;
        unsigned int pos = input.find(delimiter);
        while (pos != std::string::npos) {
            output.push_back(input.substr(lastpos, pos - lastpos));
            lastpos = pos + delimiter.size();
            pos = input.find(delimiter, lastpos);
        }
        output.push_back(input.substr(lastpos));
    } else if (limit > 0) {
        unsigned int lastpos = 0;
        unsigned int pos = input.find(delimiter);
        for (int i = 1; (i < limit) && (pos != std::string::npos); ++i) {
            output.push_back(input.substr(lastpos, pos - lastpos));
            lastpos = pos + delimiter.size();
            pos = input.find(delimiter, lastpos);
        }
        output.push_back(input.substr(lastpos));
    }
}

static void spec_trim(std::string& s) {
    unsigned int r = s.find_first_not_of(" \x0D\x0A" NEWLINE);
    if (r != std::string::npos) {
        s.erase(0, r);
        r = s.find_last_not_of(" \x0D\x0A" NEWLINE);
        if (r != std::string::npos) {
            s.erase(r + 1);
        }
    } else {
        s = "";
    }
}

static void string_replace(std::string& input,
                           const std::string& from,
                           const std::string& to) {
    unsigned int pos = input.find(from);
    while (pos != std::string::npos) {
        input.replace(pos, from.size(), to);
        pos = input.find(from, pos + to.size());
    }
}

static void string_replace_insensitive(std::string& input,
                                       std::string& from,
                                       const std::string& to) {
    std::string tmp = input;
    strtolower(tmp);
    strtolower(from);
    unsigned int pos = tmp.find(from);
    while (pos != std::string::npos) {
        input.replace(pos, from.size(), to);
        tmp.replace(pos, from.size(), to);
        pos = tmp.find(from, pos + to.size());
    }
}

static unsigned int parse_bracket(const std::string& input) {
    int brackets = 0;
    for (unsigned int i = 0; i < input.size(); ++i) {
        switch (input[i]) {
            case '(': brackets++; break;
            case ')':
                brackets--;
                if (brackets == 0) {
                    return i;
                }
                break;
        }
    }
    return std::string::npos;
}

static void make_execs(std::vector<std::string>& input) {
    unsigned i;
    for (i = 0; i + 2 < input.size(); ++i) {
        input[i] = "exec3(" + input[i] + "," + input[i + 1] + "," + input[i + 2] + ")";
        input.erase(input.begin() + i + 1, input.begin() + i + 3);
    }
    if (input.size() - i == 2) {
        input[i] = "exec2(" + input[i] + "," + input[i + 1] + ")";
        input.erase(input.begin() + i + 1);
    }
}

///////////////////////////////

void Replacement::c_style_replace(std::string& input) {
    unsigned int i, r, r2, j;
    std::vector<std::string> params, parts;
    std::string command_name;
    std::vector<unsigned int> tokens;
    std::vector<unsigned int> lengths;
    std::string tmp;
    std::string rest;

    // Parse the macro identifier
    r = this->from.find('(');
    command_name = this->from.substr(0, r);
    split(params, this->from.substr(r + 1, this->from.size() - r - 2), ",");  // ?
    lengths.resize(params.size());
    for (i = 0; i < params.size(); ++i) {
        spec_trim(params[i]);
        lengths[i] = params[i].size();
    }

    bool last_alpha, this_alpha = false;
    unsigned int last_part_pos = 0;
    // Parse the macro token string
    for (j = 0; j < to.size(); ++j) {
        last_alpha = this_alpha;
        this_alpha = VAR_PATTERN.find(to[j]) != std::string::npos;
        if (this_alpha && (!last_alpha)) {
            // beginning of an alphanumeric token -> compare to given tokens
            for (i = 0; i < params.size(); ++i) {
                if (to.compare(j, lengths[i], params[i]) == 0
                    && VAR_PATTERN.find(to[j + lengths[i]]) == std::string::npos) {
                    std::string tmp2 = tmp =
                        to.substr(last_part_pos, j - last_part_pos);
                    spec_trim(tmp2);
                    if (!parts.empty()) {
                        if (tmp2.compare(0, 2, "##") == 0) {
                            r = tmp.find("##");
                            tmp = tmp.substr(r + 2);
                            spec_trim(tmp);
                        }
                    }
                    if (tmp2.size() > 2) {
                        if (tmp2.compare(tmp2.size() - 2, 2, "##") == 0) {
                            r = tmp.rfind("##");
                            tmp = tmp.substr(0, r);
                            spec_trim(tmp);
                        }
                    }
                    parts.push_back(tmp);
                    tokens.push_back(i);
                    last_part_pos = j + params[i].size();
                    break;
                }
            }
        }
    }
    rest = to.substr(last_part_pos);
    if (!parts.empty()) {
        tmp = rest;
        spec_trim(tmp);
        if (tmp.compare(0, 2, "##") == 0) {
            r = rest.find("##");
            rest = rest.substr(r + 2);
            spec_trim(rest);
        }
    }
    std::vector<std::string>::size_type num_macro_params = params.size();

    // We have now:
    // command_name: Name of the current macro
    // params(): Names of its parameters (not needed anymore)
    // parts()/tokens()/rest: parts of the token string, to compose it from the
    //                        parameters

    std::string com_mid, com_last, com_params;
    tmp = "";
    r = input.find(command_name + '(');
    while (r != std::string::npos) {
        tmp += input.substr(0, r);
        com_mid = input.substr(r);

        r2 = parse_bracket(com_mid);
        if (r2 != std::string::npos) {
            com_last = com_mid.substr(r2 + 1);
            com_mid = com_mid.substr(0, r2 + 1);

            // Now we can be sure that com_mid contains only the string that is to be
            // replaced.
            com_params =
                com_mid.substr(command_name.size() + 1, r2 - command_name.size() - 1);
            unsigned int LastComma = 0;
            int Brackets = 0;
            params.clear();
            for (j = 0; j < com_params.size(); ++j) {
                switch (com_params[j]) {
                    case '(': Brackets++; break;
                    case ')': Brackets--; break;
                    case ',':
                        if (Brackets == 0) {
                            params.push_back(
                                com_params.substr(LastComma, j - LastComma));
                            LastComma = j + 1;
                        }
                }
            }
            params.push_back(com_params.substr(LastComma));
            if (params.size() == num_macro_params) {
                // compose macro
                for (i = 0; i < parts.size(); ++i) {
                    tmp += parts[i] + params[tokens[i]];
                }
                tmp += rest;
            } else {
                // wrong paramcount -> go to next occurence
                tmp += com_mid;
            }
            input = com_last;
            r = input.find(command_name + '(');
        } else {
            // possibly bracket error -> return the rest unchanged and exit
            tmp += com_mid + com_last;
            break;
        }
    }
    if (r == std::string::npos) {
        // no further matches -> return the rest unchanged and exit
        tmp += input;
    }
    input = tmp;
}

void Translator::do_replacements(std::string& input) {
    for (auto r : this->replacements) {
        switch (r.mode) {
            case REPLACE_CASE_SENSITIVE: string_replace(input, r.from, r.to); break;
            case REPLACE_CASE_INSENSITIVE:
                string_replace_insensitive(input, r.from, r.to);
                break;
            case REPLACE_C_STYLE: r.c_style_replace(input); break;
        }
    }
}

void Translator::command_split(std::vector<std::string>& output, std::string input) {
    unsigned int last_semicolon = 0, i;
    int brackets = 0;
    output.clear();
    input += ';';
    for (i = 0; i < input.size(); ++i) {
        switch (input[i]) {
            case '(': brackets++; break;
            case ')': brackets--; break;
            case ';':
                if (brackets == 0) {
                    output.push_back(input.substr(last_semicolon, i - last_semicolon));
                    last_semicolon = i + 1;
                }
                break;
        }
    }
    if (brackets != 0) {
        output.clear();
        string_replace(input, "=", "dummyequaldummy");
        string_replace(input, ";", "dummysemicolondummy");
        string_replace(input, "(", "[");
        string_replace(input, ")", "]");
        std::ostringstream tmp;
        tmp << brackets;
        output.push_back("BRACKETS[" + tmp.str() + "]->" + input + "<-BRACKETS");
    }
}

std::string Translator::transform_code(std::string input, int indent, bool do_parse) {
    std::vector<std::string> in_field, tmp_field;
    std::string tmp_item;
    std::vector<std::string> out_field;
    std::string tmp_linear_form, tmp_assign_form, tmp_exec_form, tmp_plus_form;
    this->command_split(in_field, input);
    out_field.clear();
    for (unsigned int i = 0; i < in_field.size(); ++i) {
        tmp_item = in_field[i];
        spec_trim(tmp_item);
        if (!tmp_item.empty()) {
            tmp_linear_form += tmp_item + ";" NEWLINE;
            tmp_item = this->parse_command(tmp_item, indent);
            split(tmp_field, tmp_item, "=", 2);  // a=b=c; changed here (3->2)
            switch (tmp_field.size()) {
                case 1:  // is already a command => no change
                    break;
                case 2:  // is an assignment => transform to assign()
                    if (tmp_field[1].find("=") != std::string::npos) {
                        // a=b=c; added here
                        tmp_item = "assign(" + tmp_field[0] + ","
                                   + this->transform_code(tmp_field[1], indent, true)
                                   + ")";
                    } else if (do_parse
                               || (tmp_field[0].find("megabuf[") != std::string::npos)
                               || (tmp_field[0].find("megabuf(")
                                   != std::string::npos)) {
                        tmp_item = "assign(" + tmp_field[0] + "," + tmp_field[1] + ")";
                    }
                    break;
                default:  // Syntax Error
                    tmp_item = "ERR->" + tmp_item + "<-ERR";
            }
            tmp_assign_form += tmp_item + ";" NEWLINE;
            out_field.push_back(tmp_item);
        }
    }
    if (do_parse) {
        join(tmp_plus_form, out_field, "+" NEWLINE + std::string(indent, ' '));
        while (out_field.size() > 1) {
            make_execs(out_field);
        }
        if (out_field.empty()) {
            tmp_exec_form = "";
        } else {
            tmp_exec_form = out_field[0];
        }
    } else {
        join(tmp_exec_form, out_field, ";" NEWLINE);
        join(tmp_plus_form, out_field, ";" NEWLINE);
    }

    switch (this->mode) {
        case MODE_LINEAR: return tmp_linear_form;
        case MODE_ASSIGN: return tmp_assign_form;
        case MODE_EXEC: return tmp_exec_form;
        case MODE_PLUS: return tmp_plus_form;
        default: return tmp_exec_form;
    }
}

std::string Translator::parse_command(std::string input, int indent) {
    std::string tmp_output;
    unsigned int r, r2, last_comma;
    unsigned int i;
    int brackets = 0;
    std::string cmd_name, cmd_params;
    r = input.find('(');
    if (r != std::string::npos) {
        r2 = parse_bracket(input);
        if (r2 == std::string::npos) {
            string_replace(input, "=", "dummyequaldummy");
            string_replace(input, ";", "dummysemicolondummy");
            string_replace(input, "(", "[");
            string_replace(input, ")", "]");
            return "BRACKETS[?]->" + input + "<-BRACKETS";
        }
        cmd_name = input.substr(0, r);
        cmd_params = input.substr(r + 1, r2 - r - 1);
        tmp_output = cmd_name + "(";
        last_comma = 0;
        for (i = 0; i < cmd_params.size(); ++i) {
            switch (cmd_params[i]) {
                case '(': brackets++; break;
                case ')': brackets--; break;
                case ',':
                    if (brackets == 0) {
                        tmp_output += this->transform_code(
                                          cmd_params.substr(last_comma, i - last_comma),
                                          indent + 1,
                                          true)
                                      + ',';
                        last_comma = i + 1;
                    }
                    break;
            }
        }
        return tmp_output
               + this->transform_code(cmd_params.substr(last_comma), indent + 1, true)
               + ')' + this->parse_command(input.substr(r2 + 1), indent);

    } else {
        return input;
    }
}

std::string Translator::handle_preprocessor(std::string input) {
    std::vector<std::string> tmp;
    split(tmp, input, " ", 3);
    if (tmp.size() > 0) {
        if (tmp[0] == "define") {
            if (tmp.size() == 3) {
                this->replacements.push_back(Replacement(
                    tmp[1],
                    tmp[2],
                    (tmp[1].find('(') == std::string::npos) ? REPLACE_CASE_INSENSITIVE
                                                            : REPLACE_C_STYLE));
            }
            return "";
        } else if (tmp[0] == "include") {
            if (tmp.size() >= 2) {
                std::string filename = this->avs_base_path + '\\' + input.substr(8);
                std::ifstream incifstr(filename.c_str());
                if (incifstr) {
                    std::ostringstream incstrstr;
                    incstrstr << incifstr.rdbuf();
                    return ";" NEWLINE + incstrstr.str() + NEWLINE ";";
                }
            }
        }
    }
    return "";
}

void Translator::handle_comment(std::string const& comment) {
    if (comment[0] != '$') {
        return;
    }
    unsigned int split_index = comment.find('=');
    unsigned int r;
    std::string tmp;

    if (split_index != std::string::npos) {
        std::string left = comment.substr(1, split_index - 1);
        std::string right = comment.substr(split_index + 1);
        strtolower(left);

        if (left == "avstrans_mode") {
            if (right == "linear") {
                this->mode = MODE_LINEAR;
            } else if (right == "assign") {
                this->mode = MODE_ASSIGN;
            } else if (right == "exec") {
                this->mode = MODE_EXEC;
            } else if (right == "plus") {
                this->mode = MODE_PLUS;
            }
        } else if (left == "avstrans_transfirst") {
            if ((right == "0") || (right == "no") || (right == "off")) {
                this->trans_first = false;
            } else if ((right == "1") || (right == "on") || (right == "yes")) {
                this->trans_first = true;
            }
        } else if (left == "avstrans_replacement") {
            r = right.find("->");
            tmp = right.substr(r + 2, right.size());
            if (!tmp.empty()) {
                this->replacements.push_back(
                    Replacement(right.substr(0, r), tmp, REPLACE_CASE_INSENSITIVE));
            }
        } else if (left == "avstrans_replacement_casesens") {
            r = right.find("->");
            tmp = right.substr(r + 2, right.size());
            if (!tmp.empty()) {
                this->replacements.push_back(
                    Replacement(right.substr(0, r - 1), tmp, REPLACE_CASE_SENSITIVE));
            }
        } else if (left == "avstrans_replacement_cstyle") {
            r = right.find("->");
            tmp = right.substr(r + 2, right.size());
            if (!tmp.empty()) {
                this->replacements.push_back(
                    Replacement(right.substr(0, r - 1), tmp, REPLACE_C_STYLE));
            }
        }
    }
}

void Translator::read_settings_from_comments(std::string& input) {
    unsigned int r, r2 = std::string::npos;
    r = input.find_first_of("/#");
    while ((r != std::string::npos) && (r2 == std::string::npos)) {
        switch (input[r]) {
            case '/':
                switch (input[r + 1]) {
                    case '*':
                        r2 = input.find("*/", r);
                        if (r2 != std::string::npos) {
                            input.erase(r, r2 - r + 2);
                            r2 = std::string::npos;
                        } else {
                            input.erase(r, input.size());
                        }
                        break;
                    case '/':
                        r2 = input.find(NEWLINE, r);
                        if (r2 != std::string::npos) {
                            this->handle_comment(input.substr(r + 2, r2 - r - 2));
                            input.erase(r, r2 - r + 2);
                            r2 = std::string::npos;
                        } else {
                            this->handle_comment(input.substr(r + 2));
                            input.erase(r, input.size());
                        }
                        break;
                    default:
                        input.replace(r, 1, EELTRANS_TMP_PLACEHOLDER_STR);
                        r2 = std::string::npos;
                        break;
                }
                break;
            case '#':
                r2 = input.find(NEWLINE, r);
                if (r2 != std::string::npos) {
                    input.replace(
                        r,
                        r2 - r + 2,
                        this->handle_preprocessor(input.substr(r + 1, r2 - r - 1)));
                    r2 = std::string::npos;
                } else {
                    this->handle_preprocessor(input.substr(r + 1));
                    input.replace(
                        r,
                        input.size(),
                        this->handle_preprocessor(input.substr(r + 1, r2 - r - 1)));
                }

                break;
        }
        r = input.find_first_of("/#");
    }
    string_replace(input, EELTRANS_TMP_PLACEHOLDER_STR, "/");
}

std::string Translator::translate(const std::string& prefix_code, std::string input) {
    std::string translate_output;
    std::string translate_input = prefix_code + NEWLINE + input;

    this->read_settings_from_comments(translate_input);
    this->do_replacements(translate_input);
    translate_output = this->transform_code(translate_input, 0, this->trans_first);
    input += ";" NEWLINE;
    string_replace(input, "dummyequaldummy", "=");
    string_replace(input, "dummysemicolondummy", ";");
    string_replace(input, "[", "(");
    string_replace(input, "]", ")");

    return translate_output;
}

std::string translate(const std::string& prefix_code,
                      char const* input,
                      bool translate_firstlevel,
                      const std::string& avs_base_path) {
    Translator translator(MODE_LINEAR, translate_firstlevel, avs_base_path);
    return translator.translate(prefix_code, input);
}
