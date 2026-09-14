int global_value = 0x12345678;
int zero_value;

extern char _data_load[];
extern char _sdata[];
extern char _edata[];

int main(void)
{
//	memcpy(
//			_sdata,
//			_data_load,
//			_edata - _sdata
//	      );
//
	return global_value + zero_value;
}
