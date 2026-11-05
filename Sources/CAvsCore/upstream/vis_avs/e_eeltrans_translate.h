#include <string>

std::string translate(const std::string& prefix_code,
                      char const* input,
                      bool translate_firstlevel,
                      const std::string& avs_base_path);
