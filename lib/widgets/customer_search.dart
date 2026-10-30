import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';

class CustomerSearchWidget extends StatefulWidget {
  final Function(Customer) onCustomerSelected;
  final Function(String) onNewCustomerName;
  final String? initialValue;

  const CustomerSearchWidget({
    super.key,
    required this.onCustomerSelected,
    required this.onNewCustomerName,
    this.initialValue,
  });

  @override
  State<CustomerSearchWidget> createState() => _CustomerSearchWidgetState();
}

class _CustomerSearchWidgetState extends State<CustomerSearchWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Customer> _suggestions = [];
  bool _showSuggestions = false;
  bool _isCustomerSelected = false;
  int _searchRevision = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    final revision = ++_searchRevision;
    // Clear the parent's selection immediately, even when the field is empty.
    widget.onNewCustomerName(query);
    _isCustomerSelected = false;
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
        _isCustomerSelected = false;
      });
      return;
    }

    _isCustomerSelected = false;
    final customers = await DatabaseService.instance.searchCustomers(query);
    if (!mounted || revision != _searchRevision) return;
    setState(() {
      _suggestions = customers;
      _showSuggestions = true;
    });
  }

  void _selectCustomer(Customer customer) {
    ++_searchRevision;
    _controller.text = customer.name;
    setState(() {
      _showSuggestions = false;
      _isCustomerSelected = true;
    });
    widget.onCustomerSelected(customer);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isCustomerSelected
                  ? AppColors.gold.withValues(alpha: 0.5)
                  : AppColors.divider,
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(color: AppColors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Lütfen müşteri adı belirleyin...',
              hintStyle: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(
                _isCustomerSelected ? Icons.person : Icons.search,
                color: _isCustomerSelected
                    ? AppColors.gold
                    : AppColors.textSecondary,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        _controller.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        // Suggestions dropdown
        if (_showSuggestions && _suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _suggestions.length,
              separatorBuilder: (context, index) =>
                  Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, index) {
                final customer = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                    radius: 18,
                    child: Text(
                      customer.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    customer.name,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                    ),
                  ),
                  subtitle:
                      customer.phone != null ||
                          customer.favoriteHairstyle != null
                      ? Text(
                          [
                            if (customer.phone != null &&
                                customer.phone!.isNotEmpty)
                              '📞 ${customer.phone}',
                            if (customer.favoriteHairstyle != null &&
                                customer.favoriteHairstyle!.isNotEmpty)
                              '✂️ ${customer.favoriteHairstyle}',
                          ].join('   '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  onTap: () => _selectCustomer(customer),
                );
              },
            ),
          ),
      ],
    );
  }
}
