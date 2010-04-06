(%
 % rowl - generation 1
 % Copyright (C) 2010 nineties
 %
 % $Id: typing.rl 2010-04-06 07:51:33 nineties $
 %);

include(stddef, code);

export(init_typing, typing, void_type, char_type, int_type, float_type, double_type);

scopeid: 0;
scopeid_stack: NULL; 

varmap: NULL;   (% variable table. name -> (tyscheme, id) %);

(% p0: (scopeid-id, name) %);
varmap_hash: (p0) {
    return strhash(p0[1]) * 3+ p0[0];
};

varmap_keyequal: (p0, p1) {
    if (p0[0] != p1[0]) { return FALSE; };
    return streq(p0[1], p1[1]);
};

varmap_push: () {
    scopeid = scopeid + 1;
    vec_pushback(scopeid_stack, scopeid);
};

varmap_pop: () {
    vec_popback(scopeid_stack);
};

(% p0: name, p1: value %);
varmap_add: (p0, p1) {
    allocate(1);
    x0 = vec_at(scopeid_stack, vec_size(scopeid_stack)-1);
    map_add(varmap, mktup2(x0, p0), p1);
};

(% p0: name %);
varmap_find: (p0) {
    allocate(3);
    x0 = vec_size(scopeid_stack)-1;
    while (x0 >= 0) {
        x1 = vec_at(scopeid_stack, x0); (% scopeid-id %);
        x2 = map_find(varmap, mktup2(x1, p0));
        if (x2 != NULL) { return x2; };
        x0 = x0 - 1;
    };
    return NULL;
};

init_varmap: () {
    varmap = mkmap(&varmap_hash, &varmap_keyequal, 10);
    scopeid_stack = mkvec(0);
    varmap_push(); (% global scopeid %);
};

in_global_namespace: () {
    return vec_size(scopeid_stack) == 1;
};

tyvarmap: NULL;

tyvarid_hash: (p0) {
    return p0;
};

tyvarid_equal: (p0, p1) {
    return p0 == p1;
};

init_tyvarmap: () {
    tyvarmap = mkmap(&tyvarid_hash, &tyvarid_equal, 10);
};

not_reachable: (p0) {
    fputs(stderr, "ERROR: not reachable here\n");
    exit(1);
};

not_implemented: (p0) {
    fputs(stderr, "ERROR: not implemented\n");
    exit(1);
};

infer_funcs: [not_reachable, not_implemented, infer_integer, infer_string, not_implemented,
    infer_identifier, infer_array, infer_tuple, infer_code, infer_decl,
    infer_call, not_implemented, infer_lambda, infer_unexpr, infer_binexpr,
    infer_assign, infer_export, infer_ret, infer_retval, infer_syscall, infer_field,
    infer_fieldref, infer_typedecl
];

void_type   : NULL;
char_type   : NULL;
int_type    : NULL;
float_type  : NULL;
double_type : NULL;

init_typing: () {
    void_type   = mktup1(NODE_VOID_T);
    char_type   = mktup1(NODE_CHAR_T);
    int_type    = mktup1(NODE_INT_T);
    float_type  = mktup1(NODE_FLOAT_T);
    double_type = mktup1(NODE_DOUBLE_T);
};

infer_integer: (p0) {
    if (p0[2] == 8)  { p0[1] = char_type; return char_type; };
    if (p0[2] == 32) { p0[1] = int_type;  return int_type; };
    not_reachable();
};

infer_string: (p0) {
    p0[1] = mktup2(NODE_POINTER_T, char_type);
    return p0[1];
};

infer_identifier: (p0) {
    allocate(3);
    x0 = varmap_find(p0[2]); (% (tyscheme, id, is_global) %);
    if (x0 == NULL) {
        fputs(stderr, "ERROR: undefined variable '");
        fputs(stderr, p0[2]);
        fputs(stderr, "'\n");
        exit(1);
    };

    x1 = rename_tyscheme(x0[0]);
    p0[1] = x1[1];
    p0[3] = x0[1];
    p0[4] = x1;
    p0[5] = x0[2];

    deref(p0);

    return p0[1];
};

infer_array: (p0) {
    allocate(5);
    x0 = mktyvar();
    x1 = p0[2]; (% length %);
    x2 = 0;
    x3 = p0[3]; (% pointer to the array %);
    while (x2 < x1) {
        x4 = x3[x2];
        x4[1] = infer_item(x3[x2]);
        unify(x0, x4[1]);
        x2 = x2 + 1;
    };
    p0[1] = mktup4(NODE_ARRAY_T, x0, x1, FALSE);
    deref(p0);
    return p0[1];
};

infer_tuple: (p0) {
    allocate(5);
    x1 = p0[2]; (% length %);
    x2 = p0[3];
    x3 = memalloc(4*x1);
    x0 = 0;
    while (x0 < x1) {
        x4 = x2[x0];
        x4[1] = infer_item((p0[3])[x0]);
        x3[x0] = x4[1];
        x0 = x0 + 1;
    };
    p0[1] = mktup3(NODE_TUPLE_T, x1, x3);
    deref(p0);
    return p0[1];
};

infer_code: (p0) {
    allocate(1);
    x0 = p0[CODE_STATEMENTS];
    while (x0 != NULL) {
        infer_item(ls_value(x0));
        x0 = ls_next(x0);
    };

    p0[1] = void_type; (% code block has no type %);
    deref(p0);
    return void_type;
};

(% p0: dontcare pattern, p1: expr %);
infer_decl_dontcare: (p0, p1) {
    p0[1] = infer_item(p1);
    return p0[1];
};

(% p0: var, p1: expr %);
infer_decl_var: (p0, p1) {
    allocate(5);
    x0 = mktyvar();
    x1 = new_varid();
    x2 = in_global_namespace();
    varmap_add(p0[2], mktup3(mktyscheme(x0), x1, x2));
    x3 = infer_item(p1);
    unify(x0, x3);
    x4 = closure(x3);
    varmap_add(p0[2], mktup3(x4, x1, x2));
    if (x3 == void_type) {
	fputs(stderr, "ERROR: variable '");
	fputs(stderr, get_ident_name(p0));
	fputs(stderr, "' has void type\n");
	exit(1);
    };
    p0[1] = x3; (% type %);
    p0[3] = x1; (% variable id %);
    p0[4] = x4; (% type scheme %);
    deref_pattern(p0);
    deref(p1);

    return p0[1];
};

(% p0: tuple pattern, p1: expr %);
infer_decl_tuple: (p0, p1) {
    allocate(1);
    x0 = infer_pattern(p0);
    unify(x0, infer_item(p1));
    deref_pattern(p0);
    deref(p1);
    return p0[1];
};

infer_pattern: (p0) {
    allocate(5);
    if (p0[0] == NODE_DONTCARE) {
        x0 = mktyvar();
        p0[1] = x0;
        return x0;
    };
    if (p0[0] == NODE_IDENTIFIER) {
        (% variable pattern %);
        x0 = mktyvar(); (% type of variable %);
        x1 = new_varid();
        x2 = mktup3(mktyscheme(x0), x1, in_global_namespace());
        varmap_add(p0[2], x2);
        p0[1] = x0;
        p0[3] = x1;
        p0[4] = x2;
        deref(p0);
        return p0[1];
    };
    if (p0[0] == NODE_TUPLE) {
        x0 = p0[TUPLE_LENGTH];
        x1 = p0[TUPLE_ELEMENTS];
        x2 = memalloc(4*x0); (% element types %);
        x3 = 0;
        while (x3 < x0) {
            x4 = infer_pattern(x1[x3]);
            x2[x3] = x4;
            x3 = x3 + 1;
        };
        p0[1] = mktup3(NODE_TUPLE_T, x0, x2);
        return p0[1];
    };
    fputs(stderr, "ERROR: invalid pattern expression\n");
    exit(1);
};

(% p0: lhs, p1: rhs %);
infer_decl_impl: (p0, p1) {
    if (p0[0] == NODE_DONTCARE) {
        return infer_decl_dontcare(p0, p1);
    };
    if (p0[0] == NODE_IDENTIFIER) {
        return infer_decl_var(p0, p1);
    };
    if (p0[0] == NODE_TUPLE) {
        return infer_decl_tuple(p0, p1);
    };
    not_implemented();
};

infer_decl: (p0) {
    allocate(1);
    x0 = infer_decl_impl(p0[2], p0[3]);
    p0[1] = x0;
    deref(p0);
    return p0[1];
};


(% p0: expr %);
infer_call: (p0) {
    allocate(3);
    x0 = infer_item(p0[2]); (% function type %);
    x1 = infer_item(p0[3]); (% argument type %);
    x2 = mktyvar(); (% return type %);
    unify(x0, mktup3(NODE_LAMBDA_T, x1, x2));

    p0[1] = x2;
    deref(p0);
    return p0[1];
};

(% insert missing return statement. p0: code block %);
insert_ret: (p0) {
    p0[CODE_STATEMENTS] = insert_ret_impl(p0[CODE_STATEMENTS]);
    return p0;
};
insert_ret_impl: (p0) {
    allocate(1);
    if (p0 == NULL) { return ls_cons(mktup2(NODE_RET, NULL), NULL); };
    x0 = ls_value(p0);
    if (x0[0] == NODE_RET) { return p0; };
    if (x0[0] == NODE_RETVAL) { return p0; };
    return ls_cons(x0, insert_ret_impl(ls_next(p0)));
};

infer_lambda: (p0) {
    allocate(2);

    (% lambda opens new namespace %);
    varmap_push();
    x0 = infer_pattern(p0[LAMBDA_ARG]);

    (% pseudo return variable for type checking %);
    x1 = mktyvar();
    x2 = new_varid();
    varmap_add(".pseudo_retvar", mktup3(mktyscheme(x1), x2, FALSE));

    p0[LAMBDA_BODY] = insert_ret(p0[LAMBDA_BODY]);
    x3 = infer_item(p0[LAMBDA_BODY]);
    varmap_pop();

    p0[1] = mktup3(NODE_LAMBDA_T, x0, x1);

    deref(p0);
    return p0[1];
};

unexpr_funcs: [
    infer_unarith, infer_unarith, infer_unarith, infer_unarith, not_implemented,
    not_implemented, infer_unarith, infer_unarith, infer_unarith, infer_unarith
];

infer_unarith: (p0) {
    allocate(1);
    x0 = infer_item(p0[3]);
    unify(int_type, x0);
    p0[1] = int_type;
    return int_type;
};

infer_unexpr: (p0) {
    allocate(1);
    x0 = unexpr_funcs[p0[2]];
    return x0(p0);
};

binexpr_funcs: [
    not_reachable, infer_binarith, infer_binarith, infer_binarith, infer_binarith,
    infer_binarith, infer_binarith, infer_binarith, infer_binarith, infer_binarith,
    infer_binarith, infer_binarith, infer_binarith, infer_binarith, infer_binarith,
    not_implemented, not_implemented, not_implemented, not_implemented
];

infer_binarith: (p0) {
    allocate(2);
    x0 = infer_item(p0[3]);
    x1 = infer_item(p0[4]);
    unify(int_type, x0);
    unify(int_type, x1);
    p0[1] = int_type;
    return int_type;
};

infer_binexpr: (p0) {
    allocate(1);
    x0 = binexpr_funcs[p0[2]];
    return x0(p0);
};

infer_assign: (p0) {
    allocate(2);
    x0 = infer_item(p0[3]); (% lhs type %);
    x1 = infer_item(p0[4]); (% rhs type %);
    unify(x0, x1);
    p0[1] = x0;
    return x0;
};

infer_export: (p0) {
    infer_item(p0[1]);
    deref(p0);
    return void_type;
};

(% return; is treated as .pseudo_retvar = (); %);
infer_ret: (p0) {
    allocate(2);
    x0 = varmap_find(".pseudo_retvar"); (% (tyscheme, id) %);
    if (x0 == NULL) {
        fputs(stderr, "ERROR: return expression outside function");
        exit(1);
    };
    x1 = x0[0];
    unify(void_type, x1[1]);
    p0[1] = void_type;
    deref(p0);
    return void_type;
};

(% return e; is treated as .pseudo_retvar = e; %);
infer_retval: (p0) {
    allocate(3);
    x0 = infer_item(p0[RETVAL_VALUE]);

    x1 = varmap_find(".pseudo_retvar"); (% (tyscheme, id) %);
    if (x1 == NULL) {
        fputs(stderr, "ERROR: return expression outside function");
        exit(1);
    };

    x2 = x1[0];
    unify(x2[1], x0);
    p0[1] = void_type;
    deref(p0);
    return void_type;
};

infer_syscall: (p0) {
    infer_item(p0[2]);
    p0[1] = int_type;
    deref(p0);
    return int_type;
};

(% fieldname : expression %);
infer_field: (p0) {
    allocate(3);
    x0 = p0[2]; (% lhs %);
    if (x0[0] != NODE_IDENTIFIER) {
        fputs(stderr, "ERROR: invalid field name\n");
        exit(1);
    };
    x1 = infer_item(p0[3]);
    x2 = mktup3(NODE_NAMED_T, get_ident_name(x0), x1);
    p0[1] = x2;
    deref(p0);
    return p0[1];
};

(% p0: type, p1: field name %);
get_fieldtype: (p0, p1) {
    allocate(4);
    if (p0[0] != NODE_TUPLE_T) {
        return NULL;
    };
    x0 = p0[TUPLE_T_LENGTH];
    x1 = p0[TUPLE_T_ELEMENTS];
    x2 = 0;
    while (x2 < x0) {
        x3 = x1[x2];
        if (has_name(x3, p1)) {
            return x3[2];
        };
        x2 = x2 + 1;
    };
    return NULL;
};

infer_fieldref: (p0) {
    allocate(3);
    x0 = infer_item(p0[2]); (% lhs %);
    x1 = p0[3]; (% field name %);
    x2 = get_fieldtype(x0, x1);
    if (x2 == NULL) {
        fputs(stderr, "ERROR: field '");
        fputs(stderr, x1);
        fputs(stderr, "' not found\n");
        exit(1);
    };
    p0[1] = x2;
    deref(p0);
    return p0[1];
};

infer_typedecl: (p0) {
    (% do nothing %);
    return p0;
};

(% p0: item %);
infer_item: (p0) {
    allocate(1);
    x0 = infer_funcs[p0[0]];
    return x0(p0);
};

remove_unfreevar: (p0) {
    allocate(1);
    if (p0 == NULL) { return NULL; };
    x0 = map_find(tyvarmap, ls_value(p0));
    if (x0 == NULL) {
        p0[1] = remove_unfreevar(ls_next(p0));
        return p0;
    };
    return remove_unfreevar(ls_next(p0));
};

(% p0: type %);
closure: (p0) {
    allocate(1);
    x0 = freevar(p0);
    x0 = remove_unfreevar(x0);
    return mktup3(x0, p0);
};

(% p0, p1: type %);
unify: (p0, p1) {
    if (p0[0] == NODE_TYVAR) { return unify_tyvar(p0, p1); };
    if (p1[0] == NODE_TYVAR) { return unify_tyvar(p1, p0); };
    if (p0[0] == p1[0]) {
        if (p0[0] == NODE_VOID_T)     { return; };
        if (p0[0] == NODE_CHAR_T)     { return; };
        if (p0[0] == NODE_INT_T)      { return; };
        if (p0[0] == NODE_FLOAT_T)    { return; };
        if (p0[0] == NODE_DOUBLE_T)   { return; };
        if (p0[0] == NODE_POINTER_T)  { return unify(p0[POINTER_T_BASE], p1[POINTER_T_BASE]); };
        if (p0[0] == NODE_TUPLE_T)    { return unify_tuple_t(p0, p1); };
        if (p0[0] == NODE_ARRAY_T)    {
            unify(p0[ARRAY_T_ELEMENT], p1[ARRAY_T_ELEMENT]);
            if (p0[ARRAY_T_LENGTH] != p1[ARRAY_T_LENGTH]) {
                type_mismatch(p0, p1);
            };
            return;
        };
        if (p0[0] == NODE_LAMBDA_T) { return unify_function_t(p0, p1); };
    };
    type_mismatch(p0, p1);
};

unify_tuple_t: (p0, p1) {
    allocate(2);
    if (p0[1] != p1[1]) { type_mismatch(p0, p1); };
    x1 = p0[1]; (% length %);
    x0 = 0;
    while (x0 < x1) {
        unify((p0[2])[x0], (p1[2])[x0]);
        x0 = x0 + 1;
    };
};

unify_function_t: (p0, p1) {
    unify_tuple_t(p0[1], p1[1]);
    unify(p0[2], p1[2]);
};

(% p0: tyvar, p1, type %);
unify_tyvar: (p0, p1) {
    allocate(1);
    if (p1[0] == NODE_TYVAR) {
        if (p0[1] == p1[1]) { return; };
    };
    x0 = map_find(tyvarmap, p0[1]);
    if (x0 != NULL) {
        unify(x0[1], p1);
        return;
    };
    if (p1[0] == NODE_TYVAR) {
        x0 = map_find(tyvarmap, p1[1]);
        if (x0 != NULL) {
            unify(p0, x0[1]);
            return;
        };
    };
    occur_check(p0[1], p1);
    x0 = closure(p1);
    map_add(tyvarmap, p0[1], x0);
};

(% p0: id, p1, type %);
occur_check: (p0, p1) {
    allocate(1);
    if (p1[0] == NODE_TUPLE_T)  { return occur_check_tuple_t(p0, p1); };
    if (p1[0] == NODE_ARRAY_T)  { return occur_check(p0, p1[1]); };
    if (p1[0] == NODE_LAMBDA_T) { return occur_check_function_t(p0, p1); };
    if (p1[0] == NODE_TYVAR) {
        if (p0 == p1[1]) {
            fputs(stderr, "ERROR: infinite type\n");
            exit(1);
        };
        x0 = map_find(tyvarmap, p1[1]);
        if (x0 == NULL) { return; };
        x0 = rename_tyscheme(x0);
        occur_check(p0, x0[1]);
    };
};

occur_check_tuple_t: (p0, p1) {
    allocate(2);
    x1 = p1[1]; (% length %);
    x0 = 0;
    while (x0 < x1) {
        occur_check(p0, (p1[2])[x0]);
        x0 = x0 + 1;
    };
};

occur_check_function_t: (p0, p1) {
    occur_check_tuple_t(p0, p1[1]);
    occur_check(p0, p1[2]);
};

(% p0, p1: type %);
type_mismatch: (p0, p1) {
    fputs(stderr, "ERROR: type mismatch ");
    put_type(stderr, p0);
    fputs(stderr, " <-> ");
    put_type(stderr, p1);
    fputc(stderr, '\n');
    exit(1);
};

deref_funcs: [not_reachable, not_implemented, deref_integer, deref_string, deref_dontcare,
    deref_identifier, deref_array, deref_tuple, deref_code, deref_decl,
    deref_call, not_implemented, deref_lambda, deref_unexpr, deref_binexpr,
    deref_assign, deref_export, deref_ret, deref_retval, deref_syscall, deref_field,
    deref_fieldref, deref_typedecl
];

(% p0: item %);
deref: (p0) {
    allocate(1);
    x0 = deref_funcs[p0[0]];
    x0(p0);
};

deref_identifier: (p0) {
    p0[1] = deref_type(p0[1]);
    p0[4] = closure(p0[1]);
};

deref_dontcare: (p0) {
    p0[1] = deref_type(p0[1]);
};

deref_integer: (p0) {
    p0[1] = deref_type(p0[1]);
};

deref_string: (p0) {
    p0[1] = deref_type(p0[1]);
};

deref_array: (p0) {
    allocate(3);
    x0 = p0[2]; (% length %);
    x1 = 0;
    while (x1 < x0) {
        x2 = p0[3];
        deref(x2[x1]);
        x1 = x1 + 1;
    };
    p0[1] = deref_type(p0[1]);
};

deref_tuple: (p0) {
    allocate(3);
    x0 = p0[2]; (% length %);
    x1 = 0;
    while (x1 < x0) {
        x2 = p0[3];
        deref(x2[x1]);
        x1 = x1 + 1;
    };
    p0[1] = deref_type(p0[1]);
};

deref_code: (p0) {
    allocate(1);
    x0 = p0[CODE_STATEMENTS];
    while (x0 != NULL) {
        deref(ls_value(x0));
        x0 = ls_next(x0);
    };
    p0[1] = deref_type(p0[1]);
};

deref_decl: (p0) {
    deref(p0[2]); (% lhs %);
    deref(p0[3]); (% rhs %);
    p0[1] = deref_type(p0[1]);
};

deref_call: (p0) {
    deref(p0[2]); (% function %);
    deref(p0[3]); (% argument %);
    p0[1] = deref_type(p0[1]);
};

deref_lambda: (p0) {
    deref(p0[LAMBDA_ARG]);
    deref(p0[LAMBDA_BODY]);
    p0[1] = deref_type(p0[1]);
};

deref_unexpr: (p0) {
    deref(p0[3]);
    p0[1] = deref_type(p0[1]);
};

deref_binexpr: (p0) {
    deref(p0[3]);
    deref(p0[4]);
    p0[1] = deref_type(p0[1]);
};

deref_assign: (p0) {
    deref(p0[3]);
    deref(p0[4]);
    p0[1] = deref_type(p0[1]);
};

deref_export: (p0) {
    deref(p0[1]);
};

deref_ret: (p0) {
    p0[1] = deref_type(p0[1]);
};

deref_retval: (p0) {
    deref(p0[RETVAL_VALUE]);
    p0[1] = deref_type(p0[1]);
};

deref_syscall: (p0) {
    deref(p0[2]);
    p0[1] = deref_type(p0[1]);
};

deref_field: (p0) {
    deref(p0[3]);
    p0[1] = deref_type(p0[1]);
};

deref_fieldref: (p0) {
    deref(p0[2]); (% lhs %);
    p0[1] = deref_type(p0[1]);
};

deref_typedecl: (p0) {
    (% do nothing %);
};

(% p0: type %);
deref_type: (p0) {
    allocate(3);
    if (p0[0] == NODE_TUPLE_T) {
        x0 = p0[1]; (% length %);
        x1 = 0;
        while (x1 < x0) {
            x2 = p0[2];
            x2[x1] = deref_type(x2[x1]);
            x1 = x1 + 1;
        };
        return p0;
    };
    if (p0[0] == NODE_ARRAY_T)   { p0[1] = deref_type(p0[1]); return p0; };
    if (p0[0] == NODE_LAMBDA_T) {
        p0[1] = deref_type(p0[1]);
        p0[2] = deref_type(p0[2]);
        return p0;
    };
    if (p0[0] == NODE_TYVAR) {
        x0 = map_find(tyvarmap, p0[1]); (% x0: type scheme %);
        if (x0 == NULL) { return p0; };
        x1 = x0[2];
        x1 = deref_type(x1);
        x2 = closure(x1);
        map_add(tyvarmap, p0[1], x2);
        return x1
    };
    if (p0[0] == NODE_NAMED_T) {
        p0[2] = deref_type(p0[2]);
        return p0;
    };
    return p0;
};

(% p0: pattern %);
deref_pattern: (p0) {
    allocate(3);
    if (p0[0] == NODE_DONTCARE) {
        p0[1] = deref_type(p0[1]);
        return;
    };
    if (p0[0] == NODE_IDENTIFIER) {
        p0[1] = deref_type(p0[1]);
        p0[4] = closure(p0[1]);
        return;
    };
    if (p0[0] == NODE_TUPLE) {
        x0 = p0[TUPLE_LENGTH];
        x1 = p0[TUPLE_ELEMENTS];
        x2 = 0;
        while (x2 < x0) {
            deref_pattern(x1[x2]);
            x2 = x2 + 1;
        };
        p0[1] = deref_type(p0[1]);
        return;
    };
    not_reachable();
};

(% p0: program (item list) %);
typing: (p0) {
    allocate(1);

    init_varmap();
    init_tyvarmap();

    x0 = p0[1];
    while (x0 != NULL) {
        infer_item(ls_value(x0));
        x0 = ls_next(x0);
    };
    return p0;
};
